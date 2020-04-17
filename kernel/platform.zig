const builtin = @import("builtin");

const platform_impl = switch(builtin.arch) {
    .i386 => @import("platform/platform.zig"),
    else => @compileError("Architecture Not Supported!"),
};

pub const frame_size = platform_impl.frame_size;
pub const initialize = platform_impl.initialize;
pub const panic = platform_impl.panic;
pub const kernel_offset = platform_impl.kernel_offset;
pub const kernel_real_start = platform_impl.kernel_real_start;
pub const kernel_real_end = platform_impl.kernel_real_end;
pub const kernel_virtual_start = platform_impl.kernel_virtual_start;
pub const kernel_virtual_end = platform_impl.kernel_virtual_end;
pub const kernel_size = platform_impl.kernel_size;
