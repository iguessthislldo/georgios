const builtin = @import("builtin");
const build_options = @import("build_options");

pub const platform = @import("platform.zig");
pub const print = @import("print.zig");
pub const Memory = @import("memory.zig").Memory;
pub const io = @import("io.zig");
pub const elf = @import("elf.zig");

pub var panic_message: []const u8 = "";

pub fn panic(msg: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panic_message = msg;
    if (trace) |t| {
        print.format("index: {}\n", t.index);
        for (t.instruction_addresses) |addr| {
            if (addr == 0) break;
            print.format(" - {:a}\n", addr);
        }
    } else {
        print.string("No Stack Trace\n");
    }
    platform.panic(msg, trace);
}

const utf32 = [_]u32 {
    0x0020,
    0x263a,
    0x263b,
    0x2665,
    0x2666,
    0x2663,
    0x2660,
    0x2022,
    0x25d8,
    0x25cb,
    0x25d9,
    0x2642,
    0x2640,
    0x266a,
    0x266b,
    0x263c,
    0x25ba,
    0x25c4,
    0x2195,
    0x203c,
    0x00b6,
    0x00a7,
    0x25ac,
    0x21a8,
    0x2191,
    0x2193,
    0x2192,
    0x2190,
    0x221f,
    0x2194,
    0x25b2,
    0x25bc,
    0x0020,
    0x0021,
    0x0022,
    0x0023,
    0x0024,
    0x0025,
    0x0026,
    0x0027,
    0x0028,
    0x0029,
    0x002a,
    0x002b,
    0x002c,
    0x002d,
    0x002e,
    0x002f,
    0x0030,
    0x0031,
    0x0032,
    0x0033,
    0x0034,
    0x0035,
    0x0036,
    0x0037,
    0x0038,
    0x0039,
    0x003a,
    0x003b,
    0x003c,
    0x003d,
    0x003e,
    0x003f,
    0x0040,
    0x0041,
    0x0042,
    0x0043,
    0x0044,
    0x0045,
    0x0046,
    0x0047,
    0x0048,
    0x0049,
    0x004a,
    0x004b,
    0x004c,
    0x004d,
    0x004e,
    0x004f,
    0x0050,
    0x0051,
    0x0052,
    0x0053,
    0x0054,
    0x0055,
    0x0056,
    0x0057,
    0x0058,
    0x0059,
    0x005a,
    0x005b,
    0x005c,
    0x005d,
    0x005e,
    0x005f,
    0x0060,
    0x0061,
    0x0062,
    0x0063,
    0x0064,
    0x0065,
    0x0066,
    0x0067,
    0x0068,
    0x0069,
    0x006a,
    0x006b,
    0x006c,
    0x006d,
    0x006e,
    0x006f,
    0x0070,
    0x0071,
    0x0072,
    0x0073,
    0x0074,
    0x0075,
    0x0076,
    0x0077,
    0x0078,
    0x0079,
    0x007a,
    0x007b,
    0x007c,
    0x007d,
    0x007e,
    0x2302,
    0x00c7,
    0x00fc,
    0x00e9,
    0x00e2,
    0x00e4,
    0x00e0,
    0x00e5,
    0x00e7,
    0x00ea,
    0x00eb,
    0x00e8,
    0x00ef,
    0x00ee,
    0x00ec,
    0x00c4,
    0x00c5,
    0x00c9,
    0x00e6,
    0x00c6,
    0x00f4,
    0x00f6,
    0x00f2,
    0x00fb,
    0x00f9,
    0x00ff,
    0x00d6,
    0x00dc,
    0x00a2,
    0x00a3,
    0x00a5,
    0x20a7,
    0x0192,
    0x00e1,
    0x00ed,
    0x00f3,
    0x00fa,
    0x00f1,
    0x00d1,
    0x00aa,
    0x00ba,
    0x00bf,
    0x2310,
    0x00ac,
    0x00bd,
    0x00bc,
    0x00a1,
    0x00ab,
    0x00bb,
    0x2591,
    0x2592,
    0x2593,
    0x2502,
    0x2524,
    0x2561,
    0x2562,
    0x2556,
    0x2555,
    0x2563,
    0x2551,
    0x2557,
    0x255d,
    0x255c,
    0x255b,
    0x2510,
    0x2514,
    0x2534,
    0x252c,
    0x251c,
    0x2500,
    0x253c,
    0x255e,
    0x255f,
    0x255a,
    0x2554,
    0x2569,
    0x2566,
    0x2560,
    0x2550,
    0x256c,
    0x2567,
    0x2568,
    0x2564,
    0x2565,
    0x2559,
    0x2558,
    0x2552,
    0x2553,
    0x256b,
    0x256a,
    0x2518,
    0x250c,
    0x2588,
    0x2584,
    0x258c,
    0x2590,
    0x2580,
    0x03b1,
    0x00df,
    0x0393,
    0x03c0,
    0x03a3,
    0x03c3,
    0x00b5,
    0x03c4,
    0x03a6,
    0x0398,
    0x03a9,
    0x03b4,
    0x221e,
    0x03c6,
    0x03b5,
    0x2229,
    0x2261,
    0x00b1,
    0x2265,
    0x2264,
    0x2320,
    0x2321,
    0x00f7,
    0x2248,
    0x00b0,
    0x2219,
    0x00b7,
    0x221a,
    0x207f,
    0x00b2,
    0x25a0,
    0x00a0,
};


pub const Kernel = struct {
    const Files = io.Files(32);

    memory: Memory = Memory{},
    file_io: Files = Files{},
    console: ?*io.File = null,

    pub fn initialize(self: *Kernel) !void {
        // Get the Console Ready
        try self.file_io.initialize();
        self.console = try self.file_io.new_file();
        print.initialize(self.console, build_options.debug_log);

        // Do a Whole Bunch of Stuff
        try platform.initialize(self);
    }

    pub fn run(self: *Kernel) !void {
        try self.initialize();

        var file = io.File{};
        var the_file = platform.impl.ata.TheFile{};
        the_file.initialize(&file);
        print.format("size: {}\n", the_file.size);
        var elf_object = try elf.Object.from_file(&file);

        platform.impl.cga_console.print_all_characters();
        platform.impl.cga_console.new_line();
        for (utf32) |c, i| {
            platform.impl.cga_console.direct_print_char(platform.impl.cga_console.from_unicode(c).?);
            if (i % 32 == 31) {
                platform.impl.cga_console.new_line();
            }
        }
    }
};

pub export fn kernel_main() void {
    panic_message = ""; // TODO: This is garbage when a panic happens
    var kernel = Kernel{};
    if (kernel.run()) |_| {} else |e| {
        panic(@errorName(e), @errorReturnTrace());
    }
    print.string("Done\n");
    platform.done();
}
