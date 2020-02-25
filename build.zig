const builtin = @import("builtin");
const std = @import("std");

const t_path = "tmp/";
const k_path = "kernel/";
const p_path = k_path ++ "platform/";

const c_include_dirs = [_][]const u8 {
    k_path,
    p_path,
};

const c_sources = [_][]const u8 {
    p_path ++ "gdt.c",
    p_path ++ "paging.c",
    p_path ++ "idt.c",
    p_path ++ "platform.c",
    p_path ++ "irq.c",
    p_path ++ "ps2.c",

    k_path ++ "library.c",
    k_path ++ "print.c",
    k_path ++ "memory.c",
    k_path ++ "system_call.c",
};

const c_args = [_][]const u8 {
    "-std=gnu11",
    "-O0",
};

const s_sources = [_][]const u8 {
    p_path ++ "boot.s",
    p_path ++ "threading.s",
    p_path ++ "irq_handlers.s",
    p_path ++ "idt_handlers.s",
};

const ZSource = struct {
    name: []const u8,
    source: []const u8,
    pub fn init(comptime dir: []const u8, comptime name: []const u8) ZSource {
        return ZSource {
            .name = name,
            .source = dir ++ name ++ ".zig",
        };
    }
};
const z_sources = [_]ZSource {
    ZSource.init(p_path, "zplatform"),
    ZSource.init(p_path, "ps2_scan_codes"),
    ZSource.init(p_path, "cga_console"),
    ZSource.init(k_path, "io"),
    ZSource.init(p_path, "platform_initialize"),
};

const boot_path = t_path ++ "iso/boot/";

pub fn build(b: *std.build.Builder) void {
    const target = std.build.Target {
        .Cross = std.build.CrossTarget{
            .arch = .i386,
            .os = .freestanding,
            .abi = .gnu,
        },
    };

    // Kernel
    const kernel = b.addExecutable("kernel.elf", k_path ++ "kernel.zig");
    kernel.setLinkerScriptPath(p_path ++ "linking.ld");
    kernel.setTheTarget(target);
    for (z_sources) |z_source| {
        const obj = b.addObject(z_source.name, z_source.source);
        obj.setTheTarget(target);
        for (c_include_dirs) |dir| {
            obj.addIncludeDir(dir);
        }
        kernel.addObject(obj);
    }
    for (c_include_dirs) |dir| {
        kernel.addIncludeDir(dir);
    }
    for (s_sources) |s_source| {
        kernel.addAssemblyFile(s_source);
    }
    for (c_sources) |c_source| {
        kernel.addCSourceFile(c_source, c_args);
    }
    kernel.install();

    // programs/test_prog
    const test_prog = b.addExecutable("test_prog.elf", null);
    test_prog.addAssemblyFile("programs/test_prog/test_prog.s");
    test_prog.setLinkerScriptPath("programs/test_prog/test_prog.ld");
    test_prog.setTheTarget(target);
    test_prog.install();
}
