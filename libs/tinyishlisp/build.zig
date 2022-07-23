const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable("tinyish-lisp", "main.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    exe.addPackage(.{
        .name = "utils",
        .path = .{.path = "../utils/utils.zig"},
    });
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
