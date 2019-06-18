const builtin = @import("builtin");
const std = @import("std");
const fs = std.fs;
const DirectAllocator = std.heap.DirectAllocator;
const Builder = std.build.Builder;

const t_path = "tmp/";
const k_path = "kernel/";
const tk_path = t_path ++ k_path;
const p_path = k_path ++ "platform/";
const tp_path = t_path ++ p_path;

const c_include_dirs = [][]const u8{
    &k_path,
    &tk_path,
    &p_path,
    &tp_path,
};

const c_sources = [][]const u8 {
    p_path ++ "gdt.c",
    p_path ++ "paging.c",
    p_path ++ "idt.c",
    p_path ++ "platform.c",
    p_path ++ "irq.c",
    p_path ++ "ps2.c",
    p_path ++ "ata.c",
    p_path ++ "pci.c",

    k_path ++ "library.c",
    k_path ++ "print.c",
    k_path ++ "memory.c",
    k_path ++ "system_call.c",
};

const c_args = []const []const u8 {
    "-std=gnu11",
    "-O0",
    "-g",
    "-ffreestanding",
    "-nostdlib",
};

const s_sources = [][]const u8 {
    p_path ++ "boot.s",
    p_path ++ "threading.s",
    p_path ++ "irq_handlers.s",
    p_path ++ "idt_handlers.s",
};

const ZSource = struct {
    dir: []const u8,
    name: []const u8,
    source: []const u8,
    pub fn init(comptime dir: []const u8, comptime name: []const u8) ZSource {
        return ZSource {
            .dir = t_path ++ dir,
            .name = name,
            .source = dir ++ name ++ ".zig",
        };
    }
};
const z_sources = []const ZSource {
    ZSource.init(p_path, "zplatform"),
    ZSource.init(p_path, "ps2_scan_codes"),
    ZSource.init(p_path, "cga_console"),
    ZSource.init(k_path, "io"),
};
var z_objects = []?*std.build.LibExeObjStep{null} ** z_sources.len;

const boot_path = t_path ++ "iso/boot/";

pub fn build(b: *Builder) void {
    const alloc = DirectAllocator.init();

    const kernel = b.addExecutable("kernel.elf", k_path ++ "kernel.zig");
    kernel.setOutputDir(tk_path);
    kernel.setLinkerScriptPath(p_path ++ "linking.ld");
    kernel.setTarget(builtin.Arch.i386, builtin.Os.freestanding, builtin.Abi.gnu);

    var i: usize = 0;
    for (z_sources) |z_source| {
        z_objects[i] = b.addObject(z_source.name, z_source.source);
        if (z_objects[i]) |z_object| {
            z_object.setTarget(builtin.Arch.i386, builtin.Os.freestanding, builtin.Abi.gnu);
            kernel.step.dependOn(&z_object.step);
            kernel.addObject(z_object);
            z_object.setOutputDir(z_source.dir);
        }
        i += 1;
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

    b.default_step.dependOn(&kernel.step);
}
