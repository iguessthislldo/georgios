const std = @import("std");
const FileSource = std.build.FileSource;
const builtin = @import("builtin");

const utils = @import("libs/utils/utils.zig");

const t_path = "tmp/";
const k_path = "kernel/";
const p_path = k_path ++ "platform/";
const root_path = t_path ++ "root/";
const boot_path = root_path ++ "boot/";
const bin_path = root_path ++ "bin/";

const utils_pkg = std.build.Pkg{
    .name = "utils",
    .path = .{.path = "libs/utils/utils.zig"},
};
const georgios_pkg = std.build.Pkg{
    .name = "georgios",
    .path = .{.path = "libs/georgios/georgios.zig"},
    .dependencies = &[_]std.build.Pkg {
        utils_pkg,
    },
};
const tinyishlisp_pkg = std.build.Pkg{
    .name = "TinyishLisp",
    .path = .{.path = "libs/tinyishlisp/TinyishLisp.zig"},
    .dependencies = &[_]std.build.Pkg {
        utils_pkg,
    },
};

var b: *std.build.Builder = undefined;
var target: std.zig.CrossTarget = undefined;
var alloc: std.mem.Allocator = undefined;
var kernel: *std.build.LibExeObjStep = undefined;
var test_step: *std.build.Step = undefined;
const program_link_script = FileSource{.path = "programs/linking.ld"};

fn format(comptime fmt: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(alloc, fmt, args) catch unreachable;
}

fn add_tests(source: []const u8) void {
    const tests = b.addTest(source);
    tests.addPackage(utils_pkg);
    tests.addPackage(georgios_pkg);
    test_step.dependOn(&tests.step);
}

pub fn build(builder: *std.build.Builder) void {
    b = builder;
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    alloc = arena_alloc.allocator();

    const multiboot_vbe = b.option(bool, "multiboot_vbe",
        \\Ask the bootloader to switch to a graphics mode for us.
        ) orelse false;
    const vbe = b.option(bool, "vbe",
        \\Use VBE Graphics if possible.
        ) orelse multiboot_vbe;
    const debug_log = b.option(bool, "debug_log",
        \\Print debug information by default
        ) orelse true;
    const wait_for_anykey = b.option(bool, "wait_for_anykey",
        \\Wait for key press at important events
        ) orelse false;
    const direct_disk = b.option(bool, "direct_disk",
        \\Do not cache disk operations, use disk directly.
        ) orelse false;
    const run_rc = b.option(bool, "run_rc",
        \\Run /etc/rc on start
        ) orelse true;
    const halt_when_done = b.option(bool, "halt_when_done",
        \\Halt instead of shutting down.
        ) orelse false;

    target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-freestanding-gnu",
            .cpu_features = "pentiumpro"
            // TODO: This is to forbid SSE code. See SSE init code in
            // kernel_start_x86_32.zig for details.
        }) catch @panic("Failed Making Default Target"),
    });
    const platform = switch (target.cpu_arch.?) {
        .i386 => "x86_32",
        else => {
            std.debug.print("Unsupported Platform: {s}\n", .{@tagName(target.cpu_arch.?)});
            @panic("Unsupported Platform");
        },
    };

    // Set install prefix to root
    // TODO: Might break in the future?
    b.resolveInstallPrefix(root_path, .{});

    // Tests
    test_step = b.step("test", "Run Tests");
    add_tests("libs/utils/test.zig");
    add_tests("libs/georgios/test.zig");
    add_tests("libs/tinyishlisp/test.zig");
    add_tests("kernel/test.zig");

    // Kernel
    const root_file = format("{s}kernel_start_{s}.zig", .{k_path, platform});
    kernel = b.addExecutable("kernel.elf", root_file);
    kernel.override_dest_dir = std.build.InstallDir{.custom = "boot"};
    kernel.setLinkerScriptPath(std.build.FileSource.relative(p_path ++ "linking.ld"));
    kernel.setTarget(target);
    const kernel_options = b.addOptions();
    kernel_options.addOption(bool, "multiboot_vbe", multiboot_vbe);
    kernel_options.addOption(bool, "vbe", vbe);
    kernel_options.addOption(bool, "debug_log", debug_log);
    kernel_options.addOption(bool, "wait_for_anykey", wait_for_anykey);
    kernel_options.addOption(bool, "direct_disk", direct_disk);
    kernel_options.addOption(bool, "run_rc", run_rc);
    kernel_options.addOption(bool, "halt_when_done", halt_when_done);
    kernel_options.addOption(bool, "is_kernel", true);
    kernel.addOptions("build_options", kernel_options);
    // Packages
    kernel.addPackage(utils_pkg);
    kernel.addPackage(georgios_pkg);
    // System Calls
    var generate_system_calls_step = b.addSystemCommand(&[_][]const u8{
        "scripts/codegen/generate_system_calls.py"
    });
    kernel.step.dependOn(&generate_system_calls_step.step);
    // bios_int/libx86emu
    build_bios_int();
    // ACPICA
    build_acpica();
    kernel.install();
    // Generate Font
    generate_builtin_font("kernel/builtin_font.bdf")
        catch @panic("generate_builtin_font failed");

    // Programs
    build_program("shell");
    build_program("hello");
    build_program("ls");
    build_program("cat");
    build_program("snake");
    build_program("cksum");
    build_program("img");
    build_program("check-test-file");
    build_program("test-prog");
    build_program("ed");
    // build_zig_program("hello-zig");
    // build_c_program("hello-c");
}

const disable_ubsan = "-fsanitize-blacklist=misc/clang-sanitize-blacklist.txt";

fn build_bios_int() void {
    var bios_int = b.addObject("bios_int", null);
    bios_int.setTarget(target);
    const bios_int_path = p_path ++ "bios_int/";
    const libx86emu_path = bios_int_path ++ "libx86emu/";
    const pub_inc = bios_int_path ++ "public_include/";
    bios_int.addIncludeDir(libx86emu_path ++ "include/");
    bios_int.addIncludeDir(bios_int_path ++ "private_include/");
    bios_int.addIncludeDir(pub_inc);
    const sources = [_][]const u8 {
        libx86emu_path ++ "api.c",
        libx86emu_path ++ "decode.c",
        libx86emu_path ++ "mem.c",
        libx86emu_path ++ "ops2.c",
        libx86emu_path ++ "ops.c",
        libx86emu_path ++ "prim_ops.c",
        bios_int_path ++ "bios_int.c",
    };
    for (sources) |source| {
        bios_int.addCSourceFile(source, &[_][]const u8{disable_ubsan});
    }
    kernel.addObject(bios_int);
    kernel.addIncludeDir(pub_inc);
}

fn build_acpica() void {
    var acpica = b.addObject("acpica", null);
    acpica.setTarget(target);
    const components = [_][]const u8 {
        "dispatcher",
        "events",
        "executer",
        "hardware",
        "namespace",
        "parser",
        "resources",
        "tables",
        "utilities",
    };
    const acpica_path = p_path ++ "acpica/";
    const source_path = acpica_path ++ "acpica/source/";

    // Configure Source
    var configure_step = b.addSystemCommand(&[_][]const u8{
        acpica_path ++ "prepare_source.py", acpica_path});
    acpica.step.dependOn(&configure_step.step);

    // Includes
    for ([_]*std.build.LibExeObjStep{kernel, acpica}) |obj| {
        obj.addIncludeDir(acpica_path ++ "include");
        obj.addIncludeDir(source_path ++ "include");
        obj.addIncludeDir(source_path ++ "include/platform");
    }

    // Add Sources
    for (components) |component| {
        const component_path = std.fs.path.join(alloc,
            &[_][]const u8{source_path, "components", component}) catch unreachable;
        var component_dir =
            std.fs.cwd().openDir(component_path, .{.iterate = true}) catch unreachable;
        defer component_dir.close();
        var walker = component_dir.walk(alloc) catch unreachable;
        while (walker.next() catch unreachable) |i| {
            const path = i.path;
            if (std.mem.endsWith(u8, path, ".c") and
                    !std.mem.endsWith(u8, path, "dump.c")) {
                const full_path = std.fs.path.join(alloc,
                    &[_][]const u8{component_path, path}) catch unreachable;
                // std.debug.print("acpica source: {s}\n", .{full_path});
                acpica.addCSourceFile(b.dupe(full_path), &[_][]const u8{disable_ubsan});
            }
        }
    }
    kernel.addObject(acpica);

    // var crt0 = b.addObject("crt0", "libs/georgios/georgios.zig");
    // crt0.addBuildOption(bool, "is_crt", true);
    // crt0.override_dest_dir = std.build.InstallDir{.Custom = "lib"};
    // crt0.setTarget(target);
    // crt0.addPackage(utils_pkg);
    // crt0.install();
}

fn build_program(name: []const u8) void {
    const elf = format("{s}.elf", .{name});
    const zig = format("programs/{s}/{s}.zig", .{name, name});
    const prog = b.addExecutable(elf, zig);
    prog.setLinkerScriptPath(program_link_script);
    prog.setTarget(target);
    prog.addPackage(georgios_pkg);
    prog.addPackage(tinyishlisp_pkg);
    prog.install();
}

fn build_zig_program(name: []const u8) void {
    const elf = format("{s}.elf", .{name});
    const zig = format("programs/{s}/{s}.zig", .{name, name});
    const prog = b.addExecutable(elf, zig);
    prog.setLinkerScriptPath(program_link_script);
    prog.setTarget(
        std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-georgios-gnu",
            .cpu_features = "pentiumpro"
        }) catch @panic("Failed Making Default Target")
    );
    prog.install();
}
// fn add_libc(what: *std.build.LibExeObjStep) void {
//     what.addLibPath("/data/development/os/newlib/newlib/i386-pc-georgios/newlib");
//     what.addSystemIncludeDir("/data/development/os/newlib/newlib/newlib/libc/include");
//     what.linkSystemLibraryName("c");
// }

fn build_c_program(name: []const u8) void {
    const elf = format("{s}.elf", .{name});
    const c = format("programs/{s}/{s}.c", .{name, name});
    const prog = b.addExecutable(elf, null);
    prog.addCSourceFile(c, &[_][]const u8{"--libc /data/development/os/georgios/newlib"});
    // add_libc(prog);
    prog.setLinkerScriptPath(program_link_script);
    prog.setTarget(
        std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-georgios-gnu",
            .cpu_features = "pentiumpro"
        }) catch @panic("Failed Making Default Target")
    );
    prog.install();
}

fn generate_builtin_font(bdf_path: []const u8) !void {
    const dir: std.fs.Dir = std.fs.cwd();

    // For reading the BDF File
    const bdf_file = try dir.openFile(bdf_path, .{.read = true});
    defer bdf_file.close();
    const reader = bdf_file.reader();
    var buffer: [512]u8 = undefined;
    var got: usize = 1;

    // For parsing the BDF File
    var chunk: []const u8 = buffer[0..0];
    var chunk_pos: usize = 0;
    var parser = utils.Bdf.Parser{};

    // For writing the generated font file
    const font_file = try dir.createFile("kernel/builtin_font_data.zig", .{});
    defer font_file.close();
    const writer = font_file.writer();

    var glyphs: []utils.Bdf.Glyph = undefined;
    var glyph_count: usize = 0;

    while (true) {
        const result = try parser.feed_input(chunk, &chunk_pos);
        if (result.done) break;

        if (result.glyph) |glyph| {
            glyphs[glyph_count] = glyph;
            glyph_count += 1;
        }

        if (result.need_more_input) {
            got = try reader.read(buffer[0..]);
            chunk = buffer[0..got];
            chunk_pos = 0;
        }

        if (result.need_buffer) |buffer_size| {
            glyphs = try alloc.alloc(utils.Bdf.Glyph, parser.font.glyph_count);
            parser.buffer = try alloc.alloc(u8, buffer_size);
        }
    }

    try writer.print(
        \\// THIS CAN NOT BE EDITED: This is generated by build.zig
        \\const utils = @import("utils");
        \\
        \\const BitmapFont = @import("BitmapFont.zig");
        \\
        \\pub const bdf = utils.Bdf{{
        \\    .bounds = .{{.size = .{{.x = {}, .y = {}}}}},
        \\    .glyph_count = {},
        \\    .default_codepoint = {},
        \\}};
        \\
        \\pub const glyph_indices = [_]BitmapFont.GlyphIndex{{
        \\
    , .{
        parser.font.bounds.size.x,
        parser.font.bounds.size.y,
        parser.font.glyph_count,
        parser.font.default_codepoint,
    });
    for (glyphs) |glyph, n| {
        try writer.print("    .{{.codepoint = {}, .index = {}}},\n", .{glyph.codepoint, n});
    }
    try writer.print(
        \\}};
        \\
        \\pub const bitmaps = [_]u8{{
        \\
    , .{});
    var newline: bool = undefined;
    for (parser.buffer.?) |elem, i| {
        newline = false;
        if (i % 8 == 0) {
            try writer.print("    ", .{});
        } else {
            try writer.print(" ", .{});
        }
        try writer.print("0x{x:0>2},", .{elem});
        if (i % 8 == 7) {
            newline = true;
            try writer.print("\n", .{});
        }
    }
    if (!newline) {
        try writer.print("\n", .{});
    }
    try writer.print("{s}\n", .{"};"});
}
