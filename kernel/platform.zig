const builtin = @import("builtin");

pub const platform_impl = switch(builtin.arch) {
    // x86_32
    .i386 => @import("platform/platform.zig"),
    else => @compileError("Architecture Not Supported!"),
};

pub const frame_size = platform_impl.frame_size;
pub const initialize = platform_impl.initialize;
pub const panic = platform_impl.panic;
pub const kernel_real_start = platform_impl.kernel_real_start;
pub const kernel_real_end = platform_impl.kernel_real_end;
pub const kernel_virtual_start = platform_impl.kernel_virtual_start;
pub const kernel_virtual_end = platform_impl.kernel_virtual_end;
pub const kernel_size = platform_impl.kernel_size;
pub const kernel_to_real = platform_impl.kernel_to_real;
pub const kernel_to_virutal = platform_impl.kernel_to_virutal;
pub const kernel_range_real_start_available =
    platform_impl.kernel_range_real_start_available;
pub const kernel_range_virtual_start_available =
    platform_impl.kernel_range_virtual_start_available;
pub const done = platform_impl.done;
pub const Memory = platform_impl.Memory;
