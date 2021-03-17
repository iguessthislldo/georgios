// Advanced Configuration and Power Interface (ACPI)
//  - https://en.wikipedia.org/wiki/Advanced_Configuration_and_Power_Interface
//  - https://wiki.osdev.org/ACPI
//
// ACPI Component Architecture (ACPICA)
//  - https://www.acpica.org/
//  - https://github.com/acpica/acpica
//  - https://wiki.osdev.org/ACPICA

const acpica = @cImport({
    @cInclude("georgios_acpica_wrapper.h");
});

pub fn init() void {
    // TODO
    // if (acpica.AcpiInitializeSubsystem() != acpica.Ok) {
    //     @panic("AcpiInitializeSubsystem Failed");
    // }
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

export fn AcpiOsGetThreadId() acpica.Status {
    @panic("AcpiOsGetThreadId called");
}

export fn AcpiOsSignalSemaphore() acpica.Status {
    @panic("AcpiOsSignalSemaphore called");
}

export fn AcpiOsCreateSemaphore() acpica.Status {
    @panic("AcpiOsCreateSemaphore called");
}

export fn AcpiOsFree() acpica.Status {
    @panic("AcpiOsFree called");
}

export fn AcpiOsAcquireLock() acpica.Status {
    @panic("AcpiOsAcquireLock called");
}

export fn AcpiOsReleaseLock() acpica.Status {
    @panic("AcpiOsReleaseLock called");
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

export fn AcpiOsAllocate() acpica.Status {
    @panic("AcpiOsAllocate called");
}

export fn AcpiOsCreateLock() acpica.Status {
    @panic("AcpiOsCreateLock called");
}

export fn AcpiOsDeleteLock() acpica.Status {
    @panic("AcpiOsDeleteLock called");
}

export fn AcpiOsReadPciConfiguration() acpica.Status {
    @panic("AcpiOsReadPciConfiguration called");
}

export fn AcpiOsWritePciConfiguration() acpica.Status {
    @panic("AcpiOsWritePciConfiguration called");
}

export fn AcpiOsWaitSemaphore() acpica.Status {
    @panic("AcpiOsWaitSemaphore called");
}

export fn AcpiOsStall() acpica.Status {
    @panic("AcpiOsStall called");
}

export fn AcpiOsSleep() acpica.Status {
    @panic("AcpiOsSleep called");
}

export fn AcpiOsDeleteSemaphore() acpica.Status {
    @panic("AcpiOsDeleteSemaphore called");
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

export fn AcpiOsAcquireObject() acpica.Status {
    @panic("AcpiOsAcquireObject called");
}

export fn AcpiOsReleaseObject() acpica.Status {
    @panic("AcpiOsReleaseObject called");
}

export fn AcpiOsPredefinedOverride() acpica.Status {
    @panic("AcpiOsPredefinedOverride called");
}

export fn AcpiOsTableOverride() acpica.Status {
    @panic("AcpiOsTableOverride called");
}

export fn AcpiOsPhysicalTableOverride() acpica.Status {
    @panic("AcpiOsPhysicalTableOverride called");
}

export fn AcpiOsPurgeCache() acpica.Status {
    @panic("AcpiOsPurgeCache called");
}

export fn AcpiOsCreateCache() acpica.Status {
    @panic("AcpiOsCreateCache called");
}

export fn AcpiOsDeleteCache() acpica.Status {
    @panic("AcpiOsDeleteCache called");
}

export fn AcpiOsEnterSleep() acpica.Status {
    @panic("AcpiOsEnterSleep called");
}
