// Advanced Configuration and Power Interface (ACPI)
//  - https://en.wikipedia.org/wiki/Advanced_Configuration_and_Power_Interface
//  - https://wiki.osdev.org/ACPI
//
// ACPI Component Architecture (ACPICA)
//  - https://www.acpica.org/
//  - https://github.com/acpica/acpica
//  - https://wiki.osdev.org/ACPICA

const utils = @import("utils");

const kernel = @import("root").kernel;
const print = kernel.print;

const pmemory = @import("memory.zig");
const util = @import("util.zig");
const interrupts = @import("interrupts.zig");
const segments = @import("segments.zig");
const timing = @import("timing.zig");

const acpica = @cImport({
    @cInclude("georgios_acpica_wrapper.h");
});

var page_directory: [1024]u32 = undefined;
var prev_page_directory: [1024]u32 = undefined;

pub fn check_status(comptime what: []const u8, status: acpica.Status) void {
    if (status != acpica.Ok) {
        print.format(what ++ " returned {:x}\n", .{status});
        @panic(what ++ " failed");
    }
}

pub fn init() !void {
    _ = utils.memory_set(utils.to_bytes(page_directory[0..]), 0);
    try pmemory.load_page_directory(&page_directory, &prev_page_directory);

    var status: acpica.Status = undefined;

    check_status("acpi.init: AcpiInitializeSubsystem", acpica.AcpiInitializeSubsystem());
    check_status("acpi.init: AcpiInitializeTables", acpica.AcpiInitializeTables(null, 16, 0));
    check_status("acpi.init: AcpiLoadTables", acpica.AcpiLoadTables());
    // check_status("acpi.init: AcpiEnableSubsystem",
    //     acpica.AcpiEnableSubsystem(acpica.ACPI_FULL_INITIALIZATION));
    // check_status("acpi.init: AcpiInitializeObjects",
    //     acpica.AcpiInitializeObjects(acpica.ACPI_FULL_INITIALIZATION));

    try pmemory.load_page_directory(&prev_page_directory, &page_directory);
}

pub fn power_off() void {
    const power_off_state: u8 = 5;
    print.string("Powering Off Now\n");
    // interrupts.pic.allow_irq(0, false);
    util.disable_interrupts();
    pmemory.load_page_directory(&page_directory, null)
        catch @panic("acpi.power_off: load_page_directory failed");
    check_status("acpi.power_off: AcpiEnterSleepStatePrep",
        acpica.AcpiEnterSleepStatePrep(power_off_state));
    check_status("acpi.power_off: AcpiEnterSleepState",
        acpica.AcpiEnterSleepState(power_off_state));
    @panic("acpi.power_off: reached end");
}

// OS Abstraction Layer ======================================================

export fn AcpiOsInitialize() acpica.Status {
    return acpica.Ok;
}

export fn AcpiOsTerminate() acpica.Status {
    return acpica.Ok;
}

export fn AcpiOsGetRootPointer() acpica.PhysicalAddress {
    var p: acpica.PhysicalAddress = 0;
    _ = acpica.AcpiFindRootPointer(@ptrCast([*c]acpica.PhysicalAddress, &p));
    print.format("AcpiFindRootPointer: {:a}\n", .{@intCast(usize, p)});
    return p;
}

export fn AcpiOsAllocate(size: acpica.Size) ?*c_void {
    const a = kernel.memory.small_alloc.alloc_array(u8, size) catch return null;
    return @ptrCast(*c_void, a.ptr);
}

export fn AcpiOsFree(ptr: ?*c_void) void {
    if (ptr != null) {
        kernel.memory.small_alloc.free_array(
            utils.make_const_slice(u8, @ptrCast([*]u8, ptr), 0)) catch {};
    }
}

const Sem = kernel.sync.Semaphore(acpica.Uint32);

export fn AcpiOsCreateSemaphore(
        max_units: acpica.Uint32, initial_units: acpica.Uint32,
        semaphore: **Sem) acpica.Status {
    const sem = kernel.memory.small_alloc.alloc(Sem) catch return acpica.NoMemory;
    sem.* = .{.value = initial_units};
    sem.init();
    semaphore.* = sem;
    return acpica.Ok;
}

export fn AcpiOsWaitSemaphore(
        semaphore: *Sem, units: acpica.Uint32, timeout: acpica.Uint16) acpica.Status {
    // TODO: Timeout in milliseconds
    var got: acpica.Uint32 = 0;
    while (got < units) {
        semaphore.wait() catch continue;
        got += 1;
    }
    return acpica.Ok;
}

export fn AcpiOsSignalSemaphore(semaphore: *Sem, units: acpica.Uint32) acpica.Status {
    var left: acpica.Uint32 = units;
    while (left > 0) {
        semaphore.signal() catch continue;
        left -= 1;
    }
    return acpica.Ok;
}

export fn AcpiOsDeleteSemaphore(semaphore: *Sem) acpica.Status {
    kernel.memory.small_alloc.free(semaphore) catch return acpica.BadParameter;
    return acpica.Ok;
}

const Lock = kernel.sync.Lock;

export fn AcpiOsCreateLock(lock: **Lock) acpica.Status {
    const l = kernel.memory.small_alloc.alloc(Lock) catch return acpica.NoMemory;
    l.* = .{};
    lock.* = l;
    return acpica.Ok;
}

export fn AcpiOsAcquireLock(lock: *Lock) acpica.ACPI_CPU_FLAGS {
    lock.spin_lock();
    return 0;
}

export fn AcpiOsReleaseLock(lock: *Lock, flags: acpica.ACPI_CPU_FLAGS) void {
    lock.unlock();
}

export fn AcpiOsDeleteLock(lock: *Lock) acpica.Status {
    kernel.memory.small_alloc.free(lock) catch return acpica.BadParameter;
    return acpica.Ok;
}

export fn AcpiOsGetThreadId() acpica.Uint64 {
    const t = kernel.threading_manager.current_thread orelse
        &kernel.threading_manager.boot_thread;
    return t.id;
}

export fn AcpiOsPredefinedOverride(predefined_object: *const acpica.ACPI_PREDEFINED_NAMES,
        new_value: **allowzero c_void) acpica.Status {
    new_value.* = @intToPtr(*allowzero c_void, 0);
    return acpica.Ok;
}

export fn AcpiOsTableOverride(existing: [*c]acpica.ACPI_TABLE_HEADER,
        new: [*c][*c]acpica.ACPI_TABLE_HEADER) acpica.Status {
    new.* = null;
    return acpica.Ok;
}

export fn AcpiOsPhysicalTableOverride(existing: [*c]acpica.ACPI_TABLE_HEADER,
        new_addr: [*c]acpica.ACPI_PHYSICAL_ADDRESS, new_len: [*c]acpica.Uint32) acpica.Status {
    new_addr.* = 0;
    return acpica.Ok;
}


export fn AcpiOsMapMemory(address: acpica.PhysicalAddress, size: acpica.Size) *allowzero c_void {
    const page = pmemory.page_size;
    const pmem = &kernel.memory.platform_memory;
    const addr = @intCast(usize, address);
    const start_page = utils.align_down(addr, page);
    const offset = addr % page;
    const range = pmem.get_unused_kernel_space(size + offset) catch {
        print.string("AcpiOsMapMemory: get_unused_kernel_space failed\n");
        return @intToPtr(*allowzero c_void, 0);
    };
    pmem.map(range, start_page, false) catch {
        print.string("AcpiOsMapMemory: map failed\n");
        return @intToPtr(*allowzero c_void, 0);
    };
    return @intToPtr(*allowzero c_void, range.start + offset);
}

export fn AcpiOsUnmapMemory(address: *allowzero c_void, size: acpica.Size) void {
    // TODO
}

export fn AcpiOsReadPort(address: acpica.ACPI_IO_ADDRESS,
        value: [*c]acpica.Uint32, width: acpica.UINT32) acpica.Status {
    const port = @truncate(u16, address);
    value.* = switch (width) {
        8 => util.in8(port),

        16 => util.in16(port),

        32 => util.in32(port),

        else => {
            print.format("AcpiOsReadPort: width is {}\n", .{width});
            return acpica.AE_ERROR;
        },
    };

    return acpica.Ok;
}

export fn AcpiOsWritePort(address: acpica.ACPI_IO_ADDRESS, value: acpica.Uint32,
        width: acpica.Uint32) acpica.Status {
    const port = @truncate(u16, address);
    switch (width) {
        8 => util.out8(port, @truncate(u8, value)),

        16 => util.out16(port, @truncate(u16, value)),

        32 => util.out32(port, value),

        else => {
            print.format("AcpiOsWritePort: width is {}\n", .{width});
            return acpica.AE_ERROR;
        },
    }

    return acpica.Ok;
}

var interrupt_handler: acpica.ACPI_OSD_HANDLER = null;
var interrupt_context: ?*c_void = null;
pub fn interrupt(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    if (interrupt_handler) |handler| {
        _ = handler(interrupt_context);
    }
}

export fn AcpiOsInstallInterruptHandler(number: acpica.Uint32,
        handler: acpica.ACPI_OSD_HANDLER, context: ?*c_void) acpica.Status {
    const fixed: u32 = 9;
    if (number != fixed) {
        print.format("AcpiOsInstallInterruptHandler: unexpected IRQ {}\n", .{number});
        return acpica.AE_BAD_PARAMETER;
    }

    if (interrupt_handler != null) {
        print.string("AcpiOsInstallInterruptHandler: already installed one\n");
        return acpica.AE_ALREADY_EXISTS;
    }
    interrupt_handler = handler;
    interrupt_context = context;

    interrupts.IrqInterruptHandler(fixed, interrupt).set(
        "ACPI", segments.kernel_code_selector, interrupts.kernel_flags);
    interrupts.load();

    return acpica.Ok;
}

export fn AcpiOsRemoveInterruptHandler(number: acpica.Uint32,
        routine: acpica.ACPI_OSD_HANDLER) acpica.Status {
    print.format("AcpiOsRemoveInterruptHandler: TODO {}\n", .{number});
    return acpica.Ok;
}

export fn AcpiOsEnterSleep(
        sleep_state: acpica.Uint8, reg_a: acpica.Uint32, reg_b: acpica.Uint32) acpica.Status {
    return acpica.Ok;
}

export fn AcpiOsGetTimer() acpica.Uint64 {
    @panic("AcpiOsGetTimer called");
}

export fn AcpiOsSignal(function: acpica.Uint32, info: *c_void) acpica.Status {
    @panic("AcpiOsSignal called");
}

export fn AcpiOsExecute() acpica.Status {
    @panic("AcpiOsExecute called");
}

export fn AcpiOsWaitEventsComplete() acpica.Status {
    @panic("AcpiOsWaitEventsComplete called");
}

export fn AcpiOsReadPciConfiguration() acpica.Status {
    @panic("AcpiOsReadPciConfiguration called");
}

export fn AcpiOsWritePciConfiguration() acpica.Status {
    @panic("AcpiOsWritePciConfiguration called");
}

export fn AcpiOsStall() acpica.Status {
    @panic("AcpiOsStall called");
}

export fn AcpiOsSleep() acpica.Status {
    @panic("AcpiOsSleep called");
}

export fn AcpiOsReadMemory() acpica.Status {
    @panic("AcpiOsReadMemory called");
}

export fn AcpiOsWriteMemory() acpica.Status {
    @panic("AcpiOsWriteMemory called");
}

export fn AcpiOsPrintf() acpica.Status {
    @panic("AcpiOsPrintf called");
}
