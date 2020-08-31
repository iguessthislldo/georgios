const builtin = @import("builtin");
const std = @import("std");

const t_path = "tmp/";
const k_path = "kernel/";
const p_path = k_path ++ "platform/";

const s_sources = [_][]const u8 {
    // p_path ++ "threading.s",
    // p_path ++ "irq_handlers.s",
};

const boot_path = t_path ++ "iso/boot/";

pub fn build(b: *std.build.Builder) void {
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
    kernel.install();

    // programs/test_prog
    const test_prog = b.addExecutable("test_prog.elf", "programs/test_prog/test_prog.zig");
    test_prog.setLinkerScriptPath("programs/test_prog/test_prog.ld");
    test_prog.setTheTarget(target);
    test_prog.install();
}
