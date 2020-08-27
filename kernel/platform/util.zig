pub fn out8(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn out16(port: u16, val: u16) void {
    asm volatile ("outw %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn out32(port: u16, val: u32) void {
    asm volatile ("outl %[val], %[port]" : :
        [val] "{al}" (val), [port] "N{dx}" (port));
}

pub fn in8(port: u16) u8 {
    return asm volatile ("inb %[port], %[rv]" :
        [rv] "={al}" (-> u8) : [port] "N{dx}" (port) );
}

pub fn in16(port: u16) u16 {
    return asm volatile ("inw %[port], %[rv]" :
        [rv] "={al}" (-> u16) : [port] "N{dx}" (port) );
}

pub fn in32(port: u16) u32 {
    return asm volatile ("inl %[port], %[rv]" :
        [rv] "={al}" (-> u32) : [port] "N{dx}" (port) );
}

pub fn insw(port: u16, destination: []u8) void {
    asm volatile ("rep insw" : :
        [port] "{dx}" (port),
        [dest_ptr] "{di}" (@truncate(u32, @ptrToInt(destination.ptr))),
        [dest_size] "{ecx}"  (@truncate(u32, destination.len) >> 1) :
        "memory");
}

pub fn enable_interrupts() void {
    asm volatile ("sti");
}

pub fn disable_interrupts() void {
    asm volatile ("cli");
}

pub fn halt() noreturn {
    disable_interrupts();
    asm volatile ("hlt");
    unreachable;
}

pub fn cr2() u32 {
    return asm volatile ("mov %%cr2, %[rv]" : [rv] "={eax}" (-> u32));
}

pub fn rdtsc() u64 {
    // Based on // https://github.com/ziglang/zig/issues/215#issuecomment-261581922
    // because I wasn't sure how to handle the fact rdtsc output is broken up
    // into two registers.
    const low = asm volatile ("rdtsc" : [low] "={eax}" (-> u32));
    const high = asm volatile ("movl %%edx, %[high]" : [high] "=r" (-> u32));
    return (u64(high) << 32) | u64(low);
}

pub var estimated_ticks_per_second: u64 = 0;
pub var estimated_ticks_per_millisecond: u64 = 0;
pub var estimated_ticks_per_microsecond: u64 = 0;
pub var estimated_ticks_per_nanosecond: u64 = 0;

pub fn estimate_cpu_speed() void {
    // TODO: Explain
    out8(0x61, (in8(0x61) & ~u8(0x02)) | 0x01);
    out8(0x43, 0xB0);
    out8(0x42, 0xFF);
    out8(0x42, 0xFF);

    // Measure Ticks Elapsed
    const start = rdtsc();
    while ((in8(0x61) & 0x20) == 0) {}
    estimated_ticks_per_second = (rdtsc() - start) * 1193180 / 0xFFFF;
    estimated_ticks_per_millisecond = estimated_ticks_per_second / 1000;
    estimated_ticks_per_microsecond = estimated_ticks_per_millisecond / 1000;
    estimated_ticks_per_nanosecond = estimated_ticks_per_microsecond / 1000;
}

inline fn wait_ticks(ticks: u64) void {
    const until = rdtsc() + ticks;
    while (until > rdtsc()) {
        asm volatile ("nop");
    }
}

pub fn wait_seconds(seconds: u64) void {
    wait_ticks(seconds * estimated_ticks_per_second);
}

pub fn wait_milliseconds(seconds: u64) void {
    wait_ticks(seconds * estimated_ticks_per_millisecond);
}

pub fn wait_microseconds(seconds: u64) void {
    wait_ticks(seconds * estimated_ticks_per_microsecond);
}

pub fn wait_nanoseconds(seconds: u64) void {
    wait_ticks(seconds * estimated_ticks_per_nanosecond);
}
