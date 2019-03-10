#include "pci.h"
#include "ata.h"

#include <print.h>

void check_bus(u1 bus);

void check_function(u1 bus, u1 device, u1 function) {
    u2 class = get_class(bus, device, function);
    if (class == 0x0604) { // PCI_TO_PCI Bridge
        check_bus(pci_read_config1(bus, device, function, 0x19));
    } else {
        print_string("Found PCI Device: ");
        switch (class) {
        case 0x0101:
            print_string("IDE Controller");
            break;
        case 0x0102:
            print_string("Floppy Disk Controller");
            break;
        case 0x0105:
            print_string("ATA Controller");
            break;
        case 0x0106:
            print_string("SATA Controller");
            break;
        case 0x0200:
            print_string("Ethernet Controller");
            break;
        case 0x0300:
            print_string("VGA Controller");
            break;
        case 0x0600:
            print_string("PCI Host Bridge");
            break;
        case 0x0601:
            print_string("ISA Bridge");
            break;
        case 0x0C03:
            print_string("USB Controler");
            break;
        default:
            print_hex(class);
        }
        print_format(" at ({d}, {d}, {d})\n", bus, device, function);

        if (class == 0x0101) ata_initialize_controller(bus, device, function);
    }
}

void check_device(u1 bus, u1 device) {
    if (get_vendor_id(bus, device, 0) == 0xFFFF) return;
    check_function(bus, device, 0);
    if (get_header_type(bus, device, 0) & 0x80) {
        // Header Type is Multi-Function, Check Them
        for (u1 f = 1; f < 8; f++) {
            if (get_vendor_id(bus, device, f) != 0xFFFF) {
                check_function(bus, device, f);
            }
        }
    }
}

void check_bus(u1 bus) {
    for (u1 i = 0; i < 32; i++) check_device(bus, i);
}

void find_pci_devices() {
    pci_device_count = 0;
    check_bus(0);
}
