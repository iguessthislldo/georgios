/*
 * PCI Interface
 * Based on https://wiki.osdev.org/PCI
 */
#ifndef X86_32_PCI_HEADER
#define X86_32_PCI_HEADER

#include <basic_types.h>
#include "io.h"

#define MAX_PCI_DEVICES 64
struct PCI_Device {
    u1 bus;
} PCI_Devices [MAX_PCI_DEVICES];
u1 pci_device_count;

/* Fields Common to all PCI Structures
 * Offset | Size | Name
 * 0x00   | 2    | Vendor ID
 * 0x02   | 2    | Device ID
 * 0x04   | 2    | Command
 * 0x06   | 2    | Status
 * 0x08   | 1    | Revision ID
 * 0x09   | 1    | Prog IF
 * 0x0A   | 1    | Subclass
 * 0x0B   | 1    | Class
 * 0x0C   | 1    | Cache Line Size
 * 0x0D   | 1    | Latency Timer
 * 0x0E   | 1    | Header Type
 * 0x0F   | 1    | BIST
 */

static inline u4 pci_read_config4(u1 bus, u1 device, u1 function, u1 offset) {
    u4 request = (((u4)1) << 31)
        | (((u4) bus) << 16)
        | (((u4) device) << 11)
        | (((u4) function) << 8)
        | (offset & 0xFC);
    out4(0x0CF8, request);
    return in4(0x0CFC);
}

static inline u2 pci_read_config2(u1 bus, u1 device, u1 function, u1 offset) {
    return (pci_read_config4(bus, device, function, offset) >> ((offset & 2) * 8)) & 0xFFFF;
}

static inline u1 pci_read_config1(u1 bus, u1 device, u1 function, u1 offset) {
    return (pci_read_config4(bus, device, function, offset) >> (offset * 8)) & 0xFF;
}

static inline u2 get_vendor_id(u1 bus, u1 device, u1 function) {
    return pci_read_config2(bus, device, function, 0);
}

static inline u2 get_class(u1 bus, u1 device, u1 function) {
    return pci_read_config2(bus, device, function, 0xB);
}

static inline u1 get_header_type(u1 bus, u1 device, u1 function) {
    return pci_read_config1(bus, device, function, 0xE);
}

void find_pci_devices();

#endif
