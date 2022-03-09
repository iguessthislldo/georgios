const std = @import("std");
const builtin = std.builtin;

const t_path = "tmp/";
const k_path = "kernel/";
const p_path = k_path ++ "platform/";
const root_path = t_path ++ "root/";
const boot_path = root_path ++ "boot/";
const bin_path = root_path ++ "bin/";

const utils_pkg = std.build.Pkg{
    .name = "utils",
    .path = "libs/utils/utils.zig",
};
const georgios_pkg = std.build.Pkg{
    .name = "georgios",
    .path = "libs/georgios/georgios.zig",
    .dependencies = &[_]std.build.Pkg {
        utils_pkg,
    },
};

var b: *std.build.Builder = undefined;
var target: std.zig.CrossTarget = undefined;
var alloc: *std.mem.Allocator = undefined;
var kernel: *std.build.LibExeObjStep = undefined;
var build_mode: builtin.Mode = undefined;
var test_step: *std.build.Step = undefined;

fn format(comptime fmt: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(alloc, fmt, args) catch unreachable;
}

fn add_tests(source: []const u8) void {
    const tests = b.addTest(source);
    tests.setBuildMode(build_mode);
    tests.addPackage(utils_pkg);
    tests.addPackage(georgios_pkg);
    test_step.dependOn(&tests.step);
}

pub fn build(builder: *std.build.Builder) void {
    b = builder;
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    alloc = &arena_alloc.allocator;

    build_mode = b.standardReleaseOptions();
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
            std.debug.warn("Unsupported Platform: {s}\n", .{@tagName(target.cpu_arch.?)});
            @panic("Unsupported Platform");
        },
    };

    // Set install prefix to root
    // TODO: Might break in the future?
    b.resolveInstallPrefix(root_path);

    // Tests
    test_step = b.step("test", "Run Tests");
    add_tests("libs/utils/test.zig");
    add_tests("libs/georgios/test.zig");
    add_tests("kernel/test.zig");

    // Kernel
    const root_file = format("{s}kernel_start_{s}.zig", .{k_path, platform});
    kernel = b.addExecutable("kernel.elf", root_file);
    kernel.override_dest_dir = std.build.InstallDir{.Custom = "boot"};
    kernel.setLinkerScriptPath(p_path ++ "linking.ld");
    kernel.setTarget(target);
    kernel.setBuildMode(build_mode);
    kernel.addBuildOption(bool, "multiboot_vbe", multiboot_vbe);
    kernel.addBuildOption(bool, "vbe", vbe);
    kernel.addBuildOption(bool, "debug_log", debug_log);
    kernel.addBuildOption(bool, "wait_for_anykey", wait_for_anykey);
    kernel.addBuildOption(bool, "is_kernel", true);
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

    // Programs
    build_program("shell");
    build_program("hello");
    build_program("ls");
    build_program("cat");
    build_program("snake");
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
        var walker = std.fs.walkPath(alloc, component_path) catch unreachable;
        while (walker.next() catch unreachable) |i| {
            const path = i.path;
            if (std.mem.endsWith(u8, path, ".c") and
                    !std.mem.endsWith(u8, path, "dump.c")) {
                // std.debug.warn("acpica source: {s}\n", .{path});
                acpica.addCSourceFile(b.dupe(path), &[_][]const u8{disable_ubsan});
            }
        }
    }
    kernel.addObject(acpica);

    // var crt0 = b.addObject("crt0", "libs/georgios/georgios.zig");
    // crt0.addBuildOption(bool, "is_crt", true);
    // crt0.override_dest_dir = std.build.InstallDir{.Custom = "lib"};
    // crt0.setTarget(target);
    // crt0.setBuildMode(build_mode);
    // crt0.addPackage(utils_pkg);
    // crt0.install();
}

fn build_program(name: []const u8) void {
    const elf = format("{s}.elf", .{name});
    const zig = format("programs/{s}/{s}.zig", .{name, name});
    const prog = b.addExecutable(elf, zig);
    prog.setLinkerScriptPath("programs/linking.ld");
    prog.setTarget(target);
    prog.addPackage(georgios_pkg);
    prog.install();
}

fn build_zig_program(name: []const u8) void {
    const elf = format("{s}.elf", .{name});
    const zig = format("programs/{s}/{s}.zig", .{name, name});
    const prog = b.addExecutable(elf, zig);
    prog.setLinkerScriptPath("programs/linking.ld");
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
    prog.setLinkerScriptPath("programs/linking.ld");
    prog.setTarget(
        std.zig.CrossTarget.parse(.{
            .arch_os_abi = "i386-georgios-gnu",
            .cpu_features = "pentiumpro"
        }) catch @panic("Failed Making Default Target")
    );
    prog.install();
}
