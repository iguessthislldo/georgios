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

const acpica = @cImport({
    @cInclude("georgios_acpica_wrapper.h");
});

pub fn init() void {
    if (acpica.AcpiInitializeSubsystem() != acpica.Ok) {
        @panic("AcpiInitializeSubsystem Failed");
    }
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

export fn AcpiOsMapMemory(address: acpica.PhysicalAddress, size: acpica.Size) *c_void {
    @panic("AcpiOsMapMemory called");
}

export fn AcpiOsUnmapMemory(address: *c_void, size: acpica.Size) void {
    @panic("AcpiOsUnmapMemory called");
    // return @intToPtr([*c]c_void, 0);
}

export fn AcpiOsGetTimer() acpica.Uint64 {
    @panic("AcpiOsGetTimer called");
}

export fn AcpiOsSignal(function: acpica.Uint32, info: *c_void) acpica.Status {
    @panic("AcpiOsSignal called");
}

export fn AcpiOsInstallInterruptHandler() acpica.Status {
    @panic("AcpiOsInstallInterruptHandler called");
}

export fn AcpiOsRemoveInterruptHandler() acpica.Status {
    @panic("AcpiOsRemoveInterruptHandler called");
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

export fn AcpiOsReadPort() acpica.Status {
    @panic("AcpiOsReadPort called");
}

export fn AcpiOsWritePort() acpica.Status {
    @panic("AcpiOsWritePort called");
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

export fn AcpiOsTableOverride() acpica.Status {
    @panic("AcpiOsTableOverride called");
}

export fn AcpiOsPhysicalTableOverride() acpica.Status {
    @panic("AcpiOsPhysicalTableOverride called");
}

export fn AcpiOsEnterSleep() acpica.Status {
    @panic("AcpiOsEnterSleep called");
}
