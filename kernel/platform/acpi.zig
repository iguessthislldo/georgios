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
const pci = @import("pci.zig");

const acpica = @cImport({
    @cInclude("georgios_acpica_wrapper.h");
});

var page_directory: [1024]u32 = undefined;
var prev_page_directory: [1024]u32 = undefined;

fn check_status(comptime what: []const u8, status: acpica.Status) void {
    if (status != acpica.Ok) {
        print.format(what ++ " returned {:x}\n", .{status});
        @panic(what ++ " failed");
    }
}

pub const TableHeader = packed struct {
    signature: [4]u8,
    size: u32,
    revision: u8,
    checksum: u8,
    // TODO: Zig Bug, stage1 panics on [6]u8
    // oem_id: [6]u8,
    oem_id1: [4]u8,
    oem_id2: [2]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: [4]u8,
    creator_revision: u32,
};

pub const Address = packed struct {
    pub const Kind = enum(u8) {
        Memory = 0,
        Io = 1,
        _,
    };

    kind: Kind,
    register_width: u8,
    register_offset: u8,
    reserved: u8,
    address: u64,
};

fn device_callback(obj: acpica.ACPI_HANDLE, level: acpica.Uint32, context: ?*anyopaque,
        return_value: [*c]?*anyopaque) callconv(.C) acpica.Status {
    _ = level;
    _ = context;
    _ = return_value;
    var devinfo: [*c]acpica.ACPI_DEVICE_INFO = undefined;
    check_status("acpi.device_callback: AcpiGetObjectInfo",
        acpica.AcpiGetObjectInfo(obj, &devinfo));
    const name = @ptrCast(*[4]u8, &devinfo.*.Name);
    print.format("   - {}\n", .{name});
    if (utils.memory_compare(name, "HPET")) {
        print.string("     - HPET Found\n");
    }
    acpica.AcpiOsFree(devinfo);
    return acpica.Ok;
}

pub fn init() !void {
    print.string(" - Initializing ACPI Subsystem\n");

    _ = utils.memory_set(utils.to_bytes(page_directory[0..]), 0);
    try pmemory.load_page_directory(&page_directory, &prev_page_directory);

    check_status("acpi.init: AcpiInitializeSubsystem", acpica.AcpiInitializeSubsystem());
    check_status("acpi.init: AcpiInitializeTables", acpica.AcpiInitializeTables(null, 16, 0));
    check_status("acpi.init: AcpiLoadTables", acpica.AcpiLoadTables());
    // check_status("acpi.init: AcpiEnableSubsystem",
    //     acpica.AcpiEnableSubsystem(acpica.ACPI_FULL_INITIALIZATION));
    // check_status("acpi.init: AcpiInitializeObjects",
    //     acpica.AcpiInitializeObjects(acpica.ACPI_FULL_INITIALIZATION));

    // var devcb_rv: ?*anyopaque = null;
    // check_status("acpi.init: AcpiGetDevices", acpica.AcpiGetDevices(
    //     null, device_callback, null, &devcb_rv));

    var table: [*c]acpica.ACPI_TABLE_HEADER = undefined;
    var hpet: [4]u8 = "HPET".*;
    check_status("acpi.init: AcpiGetTable",
        acpica.AcpiGetTable(@ptrCast([*c]u8, &hpet), 1,
            @ptrCast([*c][*c]acpica.ACPI_TABLE_HEADER, &table)));
    print.format("{}\n", .{@ptrCast(*timing.HpetTable, table).*});

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
    return p;
}

export fn AcpiOsAllocate(size: acpica.Size) ?*anyopaque {
    const a = kernel.alloc.alloc_array(u8, size) catch return null;
    return @ptrCast(*anyopaque, a.ptr);
}

export fn AcpiOsFree(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        kernel.alloc.free_array(utils.empty_slice(u8, p)) catch {};
    }
}

const Sem = kernel.sync.Semaphore(acpica.Uint32);

export fn AcpiOsCreateSemaphore(
        max_units: acpica.Uint32, initial_units: acpica.Uint32,
        semaphore: **Sem) acpica.Status {
    _ = max_units;
    const sem = kernel.alloc.alloc(Sem) catch return acpica.NoMemory;
    sem.* = .{.value = initial_units};
    sem.init();
    semaphore.* = sem;
    return acpica.Ok;
}

export fn AcpiOsWaitSemaphore(
        semaphore: *Sem, units: acpica.Uint32, timeout: acpica.Uint16) acpica.Status {
    // TODO: Timeout in milliseconds
    _ = timeout;
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
    kernel.alloc.free(semaphore) catch return acpica.BadParameter;
    return acpica.Ok;
}

const Lock = kernel.sync.Lock;

export fn AcpiOsCreateLock(lock: **Lock) acpica.Status {
    const l = kernel.alloc.alloc(Lock) catch return acpica.NoMemory;
    l.* = .{};
    lock.* = l;
    return acpica.Ok;
}

export fn AcpiOsAcquireLock(lock: *Lock) acpica.ACPI_CPU_FLAGS {
    lock.spin_lock();
    return 0;
}

export fn AcpiOsReleaseLock(lock: *Lock, flags: acpica.ACPI_CPU_FLAGS) void {
    _ = flags;
    lock.unlock();
}

export fn AcpiOsDeleteLock(lock: *Lock) acpica.Status {
    kernel.alloc.free(lock) catch return acpica.BadParameter;
    return acpica.Ok;
}

export fn AcpiOsGetThreadId() acpica.Uint64 {
    const t = kernel.threading_mgr.current_thread orelse &kernel.threading_mgr.boot_thread;
    return t.id;
}

export fn AcpiOsPredefinedOverride(predefined_object: *const acpica.ACPI_PREDEFINED_NAMES,
        new_value: **allowzero anyopaque) acpica.Status {
    _ = predefined_object;
    new_value.* = @intToPtr(*allowzero anyopaque, 0);
    return acpica.Ok;
}

export fn AcpiOsTableOverride(existing: [*c]acpica.ACPI_TABLE_HEADER,
        new: [*c][*c]acpica.ACPI_TABLE_HEADER) acpica.Status {
    _ = existing;
    new.* = null;
    return acpica.Ok;
}

export fn AcpiOsPhysicalTableOverride(existing: [*c]acpica.ACPI_TABLE_HEADER,
        new_addr: [*c]acpica.ACPI_PHYSICAL_ADDRESS, new_len: [*c]acpica.Uint32) acpica.Status {
    _ = existing;
    _ = new_len;
    new_addr.* = 0;
    return acpica.Ok;
}

export fn AcpiOsMapMemory(
        address: acpica.PhysicalAddress, size: acpica.Size) *allowzero anyopaque {
    const page = pmemory.page_size;
    const pmem = &kernel.memory_mgr.impl;
    const addr = @intCast(usize, address);
    const start_page = utils.align_down(addr, page);
    const offset = addr % page;
    const range = pmem.get_unused_kernel_space(size + offset) catch {
        print.string("AcpiOsMapMemory: get_unused_kernel_space failed\n");
        return @intToPtr(*allowzero anyopaque, 0);
    };
    pmem.map(range, start_page, false) catch {
        print.string("AcpiOsMapMemory: map failed\n");
        return @intToPtr(*allowzero anyopaque, 0);
    };
    return @intToPtr(*allowzero anyopaque, range.start + offset);
}

export fn AcpiOsUnmapMemory(address: *allowzero anyopaque, size: acpica.Size) void {
    // TODO
    _ = address;
    _ = size;
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

fn convert_pci_loc(pci_loc: [*c]acpica.ACPI_PCI_ID) pci.Location {
    // TODO ACPI_PCI_ID has a UINT16 Segment field. This might be for PCIe?
    return .{
        .bus = @intCast(pci.Bus, pci_loc.*.Bus),
        .device = @intCast(pci.Device, pci_loc.*.Device),
        .function = @intCast(pci.Function, pci_loc.*.Function),
    };
}

export fn AcpiOsReadPciConfiguration(pci_loc: [*c]acpica.ACPI_PCI_ID, offset: acpica.Uint32,
        value: [*c]acpica.Uint64, width: acpica.Uint32) acpica.Status {
    // print.format("AcpiOsReadPciConfiguration: {}\n", .{pci_loc});
    const off = @intCast(pci.Offset, offset);
    const loc = convert_pci_loc(pci_loc);
    value.* = switch (width) {
        8 => pci.read_config(u8, loc, off),

        16 => pci.read_config(u16, loc, off),

        32 => pci.read_config(u32, loc, off),

        else => {
            print.format("AcpiOsReadPciConfiguration: width is {}\n", .{width});
            return acpica.AE_ERROR;
        },
    };
    return acpica.Ok;
}

export fn AcpiOsWritePciConfiguration(pci_loc: [*c]acpica.ACPI_PCI_ID, offset: acpica.Uint32,
        value: acpica.Uint64, width: acpica.Uint32) acpica.Status {
    // print.format("AcpiOsWritePciConfiguration: {}\n", .{pci_loc});
    const off = @intCast(pci.Offset, offset);
    const loc = convert_pci_loc(pci_loc);
    switch (width) {
        8 => pci.write_config(u8, loc, off, @truncate(u8, value)),

        16 => pci.write_config(u16, loc, off, @truncate(u16, value)),

        32 => pci.write_config(u32, loc, off, @truncate(u32, value)),

        else => {
            print.format("AcpiOsWritePciConfiguration: width is {}\n", .{width});
            return acpica.AE_ERROR;
        },
    }
    return acpica.Ok;
}

var interrupt_handler: acpica.ACPI_OSD_HANDLER = null;
var interrupt_context: ?*anyopaque = null;
pub fn interrupt(interrupt_number: u32, interrupt_stack: *const interrupts.Stack) void {
    _ = interrupt_number;
    _ = interrupt_stack;
    if (interrupt_handler) |handler| {
        _ = handler(interrupt_context);
    }
}

export fn AcpiOsInstallInterruptHandler(number: acpica.Uint32,
        handler: acpica.ACPI_OSD_HANDLER, context: ?*anyopaque) acpica.Status {
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
    // TODO
    print.format("AcpiOsRemoveInterruptHandler: TODO {}\n", .{number});
    _ = number;
    _ = routine;
    return acpica.Ok;
}

export fn AcpiOsEnterSleep(
        sleep_state: acpica.Uint8, reg_a: acpica.Uint32, reg_b: acpica.Uint32) acpica.Status {
    // TODO?
    _ = sleep_state;
    _ = reg_a;
    _ = reg_b;
    return acpica.Ok;
}

export fn AcpiOsGetTimer() acpica.Uint64 {
    return 0;
    // @panic("AcpiOsGetTimer called");
}

export fn AcpiOsSignal(function: acpica.Uint32, info: *anyopaque) acpica.Status {
    _ = function;
    _ = info;
    @panic("AcpiOsSignal called");
}

export fn AcpiOsExecute() acpica.Status {
    @panic("AcpiOsExecute called");
}

export fn AcpiOsWaitEventsComplete() acpica.Status {
    @panic("AcpiOsWaitEventsComplete called");
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
