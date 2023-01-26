const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const no_max = std.math.maxInt(usize);

const utils = @import("utils");
const georgios = @import("georgios");
pub const console_writer = georgios.get_console_writer();

pub const platform = @import("platform.zig");
pub const fprint = @import("fprint.zig");
pub const print = @import("print.zig");
pub const memory = @import("memory.zig");
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");
pub const devices = @import("devices.zig");
pub const threading = @import("threading.zig");
pub const fs = @import("fs.zig");
pub const sync = @import("sync.zig");
pub const keys = @import("keys.zig");
pub const builtin_font_data = @import("builtin_font_data.zig");
pub const BitmapFont = @import("BitmapFont.zig");
pub const Console = @import("Console.zig");
pub const List = @import("list.zig").List;
pub const dispatching = @import("dispatching.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    quick_debug_ready = false; // Probably won't be able to run this anymore
    print.format("panic: {}\n", .{msg});
    platform.impl.ps2.anykey();
    panic_message = msg;
    if (trace) |t| {
        print.format("index: {}\n", .{t.index});
        for (t.instruction_addresses) |addr| {
            if (addr == 0) break;
            print.format(" - {:a}\n", .{addr});
        }
    } else {
        print.string("No Stack Trace\n");
    }
    platform.panic(msg, trace);
}

pub var memory_mgr = memory.Manager{};
pub var device_mgr = devices.Manager{};
pub var threading_mgr = threading.Manager{};
pub var filesystem_mgr: fs.Manager = undefined;

pub var alloc: *memory.Allocator = undefined;
pub var big_alloc: *memory.Allocator = undefined;
pub var console: *Console = undefined;
pub var console_file = io.File{};
// TODO: This should be builtin into the disk
pub var disk_cache_block_store: io.MemoryBlockStore = .{};
pub var builtin_font: BitmapFont = undefined;
pub var ram_disk: fs.RamDisk = undefined;

fn platform_init() !void {
    print.init(&console_file, build_options.debug_log);
    try platform.init();
    quick_debug_ready = true;
}

fn get_ext2_root() ?*fs.Vfilesystem {
    if (device_mgr.get(([_][]const u8{"ata0", "disk0"})[0..])) |disk_dev| {
        if (disk_dev.as_block_store()) |direct_block_store| {
            var use_block_store: *io.BlockStore = undefined;
            if (build_options.direct_disk) {
                use_block_store = direct_block_store;
            } else {
                disk_cache_block_store.init_as_cache(alloc.std_allocator(), direct_block_store, 128);
                use_block_store = &disk_cache_block_store.block_store_if;
            }
            if (fs.get_root(alloc, use_block_store)) |root_fs| {
                return root_fs;
            }
        }
    }
    print.string(" - No Disk Found\n");
    return null;
}

fn init() !void {
    try platform_init();

    // Filesystem
    ram_disk.init(alloc, big_alloc, platform.page_size);
    const ext2_root = get_ext2_root();
    const ram_disk_root = &ram_disk.vfs;
    filesystem_mgr.init(alloc, ext2_root orelse ram_disk_root);
    if (ext2_root != null) {
        try filesystem_mgr.mount(ram_disk_root, "/ramdisk");
    }
}

const ExecError = georgios.ExecError;

pub fn exec_elf(info: *const georgios.ProcessInfo) ExecError!threading.Process.Id {
    const process = try threading_mgr.new_process(info);
    // print.format("exec: {} {} args:\n", .{info.path, info.args.len});
    // for (info.args) |arg| {
    //     print.format("- {}\n", .{arg});
    // }
    var file_node = try filesystem_mgr.resolve_file(info.path, .{});
    var file_ctx = try file_node.open_new_context(.{.ReadOnly = .{}});
    defer file_ctx.close();
    const file_io = try file_ctx.get_io_file();
    var elf_object = try elf.Object.from_file(alloc, big_alloc, file_io);
    var segments = elf_object.segments.iterator();
    var dynamic_memory_start: usize = 0;
    while (segments.next()) |segment| {
        switch (segment.what) {
            .Data => |data| try process.address_space_copy(segment.address, data),
            .UndefinedMemory => |size| try process.address_space_set(segment.address, 0, size),
        }
        dynamic_memory_start = @maximum(segment.address + segment.size(), dynamic_memory_start);
    }
    process.entry = elf_object.header.entry;
    process.dynamic_memory.start = utils.align_up(dynamic_memory_start, platform.page_size);
    // print.format("dynamic: {:a}", .{process.dynamic_memory.start});
    try elf_object.teardown();
    try threading_mgr.start_process(process);
    return process.id;
}

const shell = "/bin/shell.elf";

pub fn exec(info: *const georgios.ProcessInfo) ExecError!threading.Process.Id {
    const std_alloc = alloc.std_allocator();

    var shebang_info: ?georgios.ProcessInfo = null;
    defer {
        if (shebang_info) |*si| {
            std_alloc.free(si.path);
            std_alloc.free(si.args);
        }
    }

    // Check for #! or ELF magic
    {
        var file_node = try filesystem_mgr.resolve_file(info.path, .{});
        var file_ctx = try file_node.open_new_context(.{.ReadOnly = .{}});
        defer file_ctx.close();
        const file_io = try file_ctx.get_io_file();
        const shebang = "#!";

        var buffer: [@maximum(shebang.len, elf.expected_magic.len)]u8 = undefined;
        const bytes = buffer[0..try file_io.read(buffer[0..])];
        if (utils.starts_with(bytes, shebang[0..])) {
            // Get program from shebang
            var al = std.ArrayList(u8).init(std_alloc);
            defer al.deinit();
            _ = try file_io.seek(shebang.len, .FromStart);
            try file_io.reader().readUntilDelimiterArrayList(&al, '\n', no_max);

            // Make new args with original path at start
            const new_args = try std_alloc.alloc([]const u8, info.args.len + 1);
            new_args[0] = info.path;
            for (info.args) |arg, i| {
                new_args[i + 1] = arg;
            }
            shebang_info = .{
                .path = al.toOwnedSlice(),
                .name = info.name,
                .args = new_args,
                .kernel_mode = info.kernel_mode,
            };
        } else if (!utils.starts_with(bytes, elf.expected_magic[0..])) {
            return ExecError.InvalidElfFile;
        }
    }

    return exec_elf(if (shebang_info) |*si| si else info);
}

fn run() !void {
    try init();
    if (!build_options.run_rc) {
        return;
    }
    print.string("\x1bc"); // Reset Console
    // try @import("sync.zig").system_tests();

    try device_mgr.print_tree(console_writer);

    const init_info: georgios.ProcessInfo = .{.path = "/etc/init"};
    const init_exit_info = try threading_mgr.wait_for_process(try exec(&init_info));
    print.format("INIT: {}\n", .{init_exit_info});
}

var quick_debug_ready = false;

// Run at anytime after platform init with Ctrl-Alt-Shift-D
pub fn quick_debug() void {
    if (!quick_debug_ready) return;
    print.string("\nSTART QUICK DEBUG =============================================================\n");
    print.format("{} processes {} threads\n",
        .{threading_mgr.process_list.len(), threading_mgr.thread_list.len()});
    // TODO: More info like memory usage
    print.string("END QUICK DEBUG ===============================================================\n");
}

pub fn kernel_main() void {
    if (run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    if (build_options.halt_when_done) {
        print.string("Kernel configured to halt forever instead of shutdown...\n");
        platform.halt_forever();
    } else {
        print.string("Shutting down...\n");
        platform.shutdown();
    }
}
