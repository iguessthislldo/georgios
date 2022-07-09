const builtin = @import("builtin");

pub const impl = switch(builtin.cpu.arch) {
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
pub const shutdown = impl.shutdown;
pub const halt_forever = impl.halt_forever;
pub const idle = impl.idle;
pub const Memory = impl.Memory;
pub const MemoryMgrImpl = impl.MemoryMgrImpl;
pub const enable_interrupts = impl.enable_interrupts;
pub const disable_interrupts = impl.disable_interrupts;
pub const Time = impl.Time;
pub const time = impl.time;
pub const seconds_to_time = impl.seconds_to_time;
pub const milliseconds_to_time = impl.milliseconds_to_time;
