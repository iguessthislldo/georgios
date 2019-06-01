#include "ata.h"
#include "pci.h"
#include "platform.h"
#include <print.h>

#define CMD_DATA 0
#define CMD_ERROR 1
#define CMD_FEATURES 1

#define CMD_SEC_COUNT 2
#define CMD_SEC_NUMBER 3

#define CMD_LBA_LOW 3
#define CMD_CYL_LOW 4
#define CMD_LBA_MID 4
#define CMD_CYL_HIGH 5
#define CMD_LBA_HIGH 5

#define CMD_HEAD 6
#define CMD_HEAD_CHS (0 << 6)
#define CMD_HEAD_LBA (1 << 6)
#define CMD_HEAD_SELECT(DRIVE) ((DRIVE) << 4)
#define CMD_STATUS 7
#define CMD_STATUS_BUSY (1 << 7)
#define CMD_STATUS_READY (1 << 6)
#define CMD_STATUS_ERROR (1 << 0)
#define CMD_COMMAND 7

#define CTL_ALT_STATUS 2
#define CTL_DEV 2
#define CTL_DEV_RESET (1 << 2)
#define CTL_DEV_INT_ENABLE (0 << 1)
#define CTL_DEV_INT_DISABLE (1 << 1)
#define CTL_ADDRESS 3

#define LEGACY_PRIMARY_CMD_BASE 0x01F0
#define LEGACY_PRIMARY_CTL_BASE 0x03F4
#define LEGACY_SECONDARY_CMD_BASE 0x0170
#define LEGACY_SECONDARY_CTL_BASE 0x0374

#define PRIMARY 0
#define SECONDARY 1
#define MASTER 0
#define SLAVE 1

typedef struct {
    u1 channel;
    u2 command_base;
    u2 control_base;
    bool initialized;
} Channel;
Channel channels[2];

static inline void cmd_reg_write(u1 channel, u2 reg, u1 data) {
    out1(channels[channel].command_base + reg, data);
}

static inline void ctl_reg_write(u1 channel, u2 reg, u1 data) {
    out1(channels[channel].control_base + reg, data);
}

static inline u1 cmd_reg_read(u1 channel, u2 reg) {
    return in1(channels[channel].command_base + reg);
}

static inline u1 ctl_reg_read(u1 channel, u2 reg) {
    return in1(channels[channel].control_base + reg);
}

/*
 * Check channel For timeout msec, return true if still busy after that time,
 * otherwise false.
 */
static inline bool channel_wait(u1 channel, u4 timeout) {
    u1 result;
    while (timeout--) {
        result = cmd_reg_read(channel, CMD_STATUS);
        if (!(result & CMD_STATUS_BUSY) && (result & CMD_STATUS_READY)) {
            return false;
        }
        msec_wait(10);
    }
    return true;
}

#define RETURN(V) return (channels[channel].initialized = (V));
/*
 * Try to Initialize Channel. Return false for error otherwise true
 */
static inline bool initialize_drive(u1 channel, u1 drive) {
    print_format("ATA {s} {s}: ",
        channel ? "SECONDARY" : "PRIMARY",
        drive ? "SLAVE" : "MASTER");
    cmd_reg_write(channel, CMD_HEAD, CMD_HEAD_SELECT(drive));
    ctl_reg_write(channel, CTL_DEV, CTL_DEV_INT_DISABLE | CTL_DEV_RESET);
    usec_wait(5);
    ctl_reg_write(channel, CTL_DEV, CTL_DEV_INT_DISABLE);
    msec_wait(3);
    if (channel_wait(channel, 30)) {
        print_string("Missing\n");
        RETURN(false);
    }
    msec_wait(2);
    u1 error = cmd_reg_read(channel, CMD_ERROR);
    u1 status = cmd_reg_read(channel, CMD_STATUS);
    if (error & 0x80 || status & 0x2D) {
        print_format("Error\n    Error is {x}, status is {x}\n", error, status);
        RETURN(false);
    }
    cmd_reg_write(channel, CMD_HEAD, CMD_HEAD_SELECT(drive));
    usec_wait(5);
    u2 count = cmd_reg_read(channel, CMD_SEC_COUNT) & 0xFF;
    u2 number = cmd_reg_read(channel, CMD_SEC_NUMBER) & 0xFF;
    if (count != 1 || number != 1) {
        print_format("Error\n    Expected 1 and 1, but got {d} and {d}\n", count, number);
        RETURN(false);
    }
    print_string("Present\n");
    RETURN(true);
}

void ata_initialize_controller(u1 bus, u1 device, u1 function) {
    u4 bar0 = pci_read_config4(bus, device, function, 0x10);
    u4 bar1 = pci_read_config4(bus, device, function, 0x14);
    u4 bar2 = pci_read_config4(bus, device, function, 0x18);
    u4 bar3 = pci_read_config4(bus, device, function, 0x1C);
    // u4 bar4 = pci_read_config4(bus, device, function, 0x20);

#define PORT(BAR, DEFAULT) (((BAR) == 0 || (BAR) == 1) ? (DEFAULT) : (BAR))
#define BYTE_MASK(VALUE) ((VALUE) & 0xFFFFFFFC)
    channels[PRIMARY].channel = PRIMARY;
    channels[PRIMARY].command_base = PORT(bar0, LEGACY_PRIMARY_CMD_BASE);
    channels[PRIMARY].control_base = PORT(bar1, LEGACY_PRIMARY_CTL_BASE);

    channels[SECONDARY].channel = SECONDARY;
    channels[SECONDARY].command_base = PORT(bar2, LEGACY_SECONDARY_CMD_BASE);
    channels[SECONDARY].control_base = PORT(bar3, LEGACY_SECONDARY_CTL_BASE);

    initialize_drive(PRIMARY, MASTER);
    initialize_drive(PRIMARY, SLAVE);
    initialize_drive(SECONDARY, MASTER);
    initialize_drive(SECONDARY, SLAVE);
}

bool ata_disk_read(u1 disk, u4 sector, mem_t dest) {
    return false;
}
