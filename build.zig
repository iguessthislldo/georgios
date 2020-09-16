const builtin = @import("builtin");
const std = @import("std");

const t_path = "tmp/";
const k_path = "kernel/";
const p_path = k_path ++ "platform/";

const s_sources = [_][]const u8 {
    p_path ++ "threading.s",
    // p_path ++ "irq_handlers.s",
};

const boot_path = t_path ++ "iso/boot/";

pub fn build(b: *std.build.Builder) void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const alloc = &arena_alloc.allocator;

    const build_mode = b.standardReleaseOptions();
    const multiboot_vga_request = b.option(bool, "multiboot_vga_request",
        \\Ask the bootloader to switch to a graphics mode for us.
        ) orelse false;
    const debug_log = b.option(bool, "debug_log",
        \\Print debug information by default
        ) orelse true;

    // TODO: Make Controllable
    const zig_arch = builtin.Arch.i386;
    const georgios_arch = "x86_32";
    const target = std.build.Target {
        .Cross = std.build.CrossTarget{
            .arch = .i386,
            .os = .freestanding,
            .abi = .gnu,
        },
    };

    // Kernel
    const kernel = b.addExecutable("kernel.elf",
        k_path ++ "kernel_start_" ++ georgios_arch ++ ".zig");
    kernel.setLinkerScriptPath(p_path ++ "linking.ld");
    kernel.setTheTarget(target);
    kernel.setBuildMode(build_mode);
    kernel.addBuildOption(bool,
        "multiboot_vga_request", multiboot_vga_request);
    kernel.addBuildOption(bool, "debug_log", debug_log);
    for (s_sources) |s_source| {
        kernel.addAssemblyFile(s_source);
    }
    // ACPICA
    {
        var acpica = b.addObject("acpica", null);
        acpica.setTheTarget(target);
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
        var configure_step = b.addSystemCommand([_][]const u8{
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
                [_][]const u8{source_path, "components", component}) catch unreachable;
            var walker = std.fs.walkPath(alloc, component_path) catch unreachable;
            var i = walker.next() catch unreachable;
            while (i != null) {
                const path = i.?.path;
                if (std.mem.endsWith(u8, path, ".c") and
                        !std.mem.endsWith(u8, path, "dump.c")) {
                    // std.debug.warn("{}\n", path);
                    acpica.addCSourceFile(path, [_][]const u8{});
                }
                i = walker.next() catch unreachable;
            }
        }
        kernel.addObject(acpica);
    }
    kernel.install();

    // libcommon
    const libcommon = b.addStaticLibrary("common", "programs/common/common.zig");
    libcommon.setTheTarget(target);

    // programs/test_prog
    const test_prog = b.addExecutable("test_prog.elf", "programs/test_prog/test_prog.zig");
    test_prog.setLinkerScriptPath("programs/common/linking.ld");
    test_prog.setTheTarget(target);
    test_prog.linkLibraryOrObject(libcommon);
    test_prog.addPackagePath("system_calls", "programs/common/system_calls.zig");
    test_prog.install();
}
