#include "ata.h"
#include "pci.h"
#include "platform.h"

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
#define CMD_STATUS 7
#define CMD_COMMAND 7

#define CTL_ALT_STATUS 2
#define CTL_DEV_CONTROL 2
#define CTL_ADDRESS 3

#define LEGACY_PRIMARY_CMD_BASE 0x01F0
#define LEGACY_PRIMARY_CTL_BASE 0x03F4
#define LEGACY_SECONDARY_CMD_BASE 0x0170
#define LEGACY_SECONDARY_CTL_BASE 0x0374

#define PRIMARY 0
#define SECONDARY 1

typedef struct {
    u1 channel;
    u2 command_base;
    u2 control_base;
} Channel;
Channel channels[2];

static inline void cmd_reg_write(u1 channel, u2 reg, u2 data) {
    out2(channels[channel].command_base + reg, data);
}

static inline void ctl_reg_write(u1 channel, u2 reg, u2 data) {
    out2(channels[channel].control_base + reg, data);
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

    // Reset Drive:
    //   Select Drive Using CMD_HEAD
    //   Set bit 2 in CTL_DEV_CONTROL
}

bool ata_disk_read(u1 disk, u4 sector, mem_t dest) {
    return false;
}
