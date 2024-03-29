// Timing Control
// Specifically for the Intel 8253 and 8354 Programmable Interval Timers
// (PITs).
//
// For Reference See:
//   https://en.wikipedia.org/wiki/Intel_8253
//   https://wiki.osdev.org/Programmable_Interval_Timer

const util = @import("util.zig");

const acpi = @import("acpi.zig");

/// Base Frequency
const oscillator: u32 = 1_193_180;

// I/O Ports
const channel_arg_base_port: u16 = 0x40;
const command_port: u16 = 0x43;
const pc_speaker_port: u16 = 0x61;

// Set Operating Mode of PITs =================================================

// Use this Python to help decode a raw command byte:
// def command(c):
//     if c & 1:
//         print("BCD")
//     print("Mode:", (c >> 1) & 7)
//     print("Access:", (c >> 4) & 3)
//     print("Channel:", (c >> 6) & 3)

const Mode = enum(u3) {
    Terminal,
    OneShot,
    Rate,
    Square,
    SwStrobe,
    HwStrobe,
    RateAgain,
    SquareAgain,
};

const Channel = enum(u2) {
    Irq0, // (Channel 0)
    Channel1, // Assume to be Unusable
    Speaker, // (Channel 2)
    Channel3, // ?

    pub fn get_arg_port(self: Channel) u16 {
        return channel_arg_base_port + @enumToInt(self);
    }
};

const Command = packed struct {
    bcd: bool = false,
    mode: Mode,
    access: enum(u2) {
        Latch,
        LowByte,
        HighByte,
        BothBytes,
    },
    channel: Channel,

    pub fn perform(self: *const Command) void {
        util.out8(command_port, @bitCast(u8, self.*));
    }
};

pub fn set_pit_both_bytes(channel: Channel, mode: Mode, arg: u16) void {
    // Issue Command
    const cmd = Command{.channel=channel, .access=.BothBytes, .mode=mode};
    cmd.perform();

    // Issue Two Byte Argument Required by BothBytes
    const port: u16 = channel.get_arg_port();
    util.out8(port, @truncate(u8, arg));
    util.out8(port, @truncate(u8, arg >> 8));
}

pub fn set_pit_freq(channel: Channel, frequency: u32) void {
    set_pit_both_bytes(channel, .Square, @truncate(u16, oscillator / frequency));
}

// PC Speaker =================================================================

fn speaker_enabled(enable: bool) callconv(.Inline) void {
    const mask: u8 = 0b10;
    const current = util.in8(pc_speaker_port);
    const desired = if (enable) current | mask else current & ~mask;
    if (current != desired) {
        util.out8(pc_speaker_port, desired);
    }
}

pub fn beep(frequency: u32, milliseconds: u64) void {
    set_pit_freq(.Speaker, frequency);
    speaker_enabled(true);
    wait_milliseconds(milliseconds);
    speaker_enabled(false);
}

// Crude rdtsc-based Timer ====================================================
// Uses the PIC and rdtsc instruction to estimate the clock speed and then use
// rdtsc as a crude timer.

pub fn rdtsc() u64 {
    // Based on https://github.com/ziglang/zig/issues/215#issuecomment-261581922
    // because I wasn't sure how to handle the fact rdtsc output is broken up
    // into two registers.
    const low = asm volatile ("rdtsc" : [low] "={eax}" (-> u32));
    const high = asm volatile ("movl %%edx, %[high]" : [high] "=r" (-> u32));
    return (@as(u64, high) << 32) | @as(u64, low);
}

pub var estimated_ticks_per_second: u64 = 0;
pub var estimated_ticks_per_millisecond: u64 = 0;
pub var estimated_ticks_per_microsecond: u64 = 0;
pub var estimated_ticks_per_nanosecond: u64 = 0;

pub fn estimate_cpu_speed() void {
    // Setup the PIT counter to count down oscillator / ticks seconds (About
    // 1.138 seconds).
    util.out8(pc_speaker_port, (util.in8(pc_speaker_port) & ~@as(u8, 0x02)) | 0x01);
    const ticks: u16 = 0xffff;
    set_pit_both_bytes(.Speaker, .Terminal, ticks);

    // Record Start rdtsc
    const start = rdtsc();

    // Wait Until PIT Counter is Zero
    while ((util.in8(pc_speaker_port) & 0x20) == 0) {}

    // Estimate CPU Tick Rate
    estimated_ticks_per_second = (rdtsc() - start) * oscillator / ticks;
    estimated_ticks_per_millisecond = estimated_ticks_per_second / 1000;
    estimated_ticks_per_microsecond = estimated_ticks_per_millisecond / 1000;
    estimated_ticks_per_nanosecond = estimated_ticks_per_microsecond / 1000;
}

pub fn seconds_to_ticks(s: u64) u64{
    return s * estimated_ticks_per_second;
}

pub fn milliseconds_to_ticks(ms: u64) u64 {
    return ms * estimated_ticks_per_millisecond;
}

fn wait_ticks(ticks: u64) callconv(.Inline) void {
    const until = rdtsc() + ticks;
    while (until > rdtsc()) {
        asm volatile ("nop");
    }
}

pub fn wait_seconds(s: u64) void {
    wait_ticks(s * estimated_ticks_per_second);
}

pub fn wait_milliseconds(ms: u64) void {
    wait_ticks(ms * estimated_ticks_per_millisecond);
}

pub fn wait_microseconds(us: u64) void {
    wait_ticks(us * estimated_ticks_per_microsecond);
}

pub fn wait_nanoseconds(ns : u64) void {
    wait_ticks(ns * estimated_ticks_per_nanosecond);
}

// High Precision Event Timer (HPET) ==========================================

pub const HpetTable = packed struct {
    pub const PageProtection = enum(u4) {
        None = 0,
        For4KibPages,
        For64KibPages,
        _,
    };

    header: acpi.TableHeader,
    hardware_rev_id: u8,
    comparator_count: u5,
    counter_size: bool,
    reserved: bool,
    legacy_replacment: bool,
    pci_vendor_id: u16,
    base_address: acpi.Address,
    hpet_number: u8,
    minimum_tick: u16,
    page_protection: PageProtection,
    oem_attrs: u4,
};
