const builtin = @import("builtin");

pub const impl = switch(builtin.arch) {
    // x86_32
    .i386 => @import("platform/platform.zig"),
    else => @compileError("Architecture Not Supported!"),
};

pub const frame_size = impl.frame_size;
pub const init = impl.init;
pub const setup_devices = impl.setup_devices;
pub const panic = impl.panic;
pub const kernel_real_start = impl.kernel_real_start;
pub const kernel_real_end = impl.kernel_real_end;
pub const kernel_virtual_start = impl.kernel_virtual_start;
pub const kernel_virtual_end = impl.kernel_virtual_end;
pub const kernel_size = impl.kernel_size;
pub const kernel_to_real = impl.kernel_to_real;
pub const kernel_to_virutal = impl.kernel_to_virutal;
pub const kernel_range_real_start_available =
    impl.kernel_range_real_start_available;
pub const kernel_range_virtual_start_available =
    impl.kernel_range_virtual_start_available;
pub const done = impl.done;
pub const Memory = impl.Memory;
