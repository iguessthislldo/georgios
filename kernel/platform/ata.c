#include "ata.h"
#include "pci.h"
#include "platform.h"

// Based on
// https://wiki.osdev.org/PCI_IDE_Controller
// http://flingos.co.uk/docs/reference/ATA/

// Don't know how to determine and/or change this. This will be an assumtion
// for now.
#define BLOCK_SIZE 512

#define ATA_LEGACY_PRIMARY_CHANNEL_BASE 0x01F0
#define ATA_LEGACY_PRIMARY_CHANNEL_CONTROL 0x03F4
#define ATA_LEGACY_SECONDARY_CHANNEL_BASE 0x0170
#define ATA_LEGACY_SECONDARY_CHANNEL_CONTROL 0x0374

#define ATA_SR_BUSY     0x80    // Busy
#define ATA_SR_DRDY    0x40    // Drive ready
#define ATA_SR_DF      0x20    // Drive write fault
#define ATA_SR_DSC     0x10    // Drive seek complete
#define ATA_SR_DRQ     0x08    // Data request ready
#define ATA_SR_CORR    0x04    // Corrected data
#define ATA_SR_IDX     0x02    // Index
#define ATA_SR_ERR     0x01    // Error

#define ATA_ER_BBK      0x80    // Bad block
#define ATA_ER_UNC      0x40    // Uncorrectable data
#define ATA_ER_MC       0x20    // Media changed
#define ATA_ER_IDNF     0x10    // ID mark not found
#define ATA_ER_MCR      0x08    // Media change request
#define ATA_ER_ABRT     0x04    // Command aborted
#define ATA_ER_TK0NF    0x02    // Track 0 not found
#define ATA_ER_AMNF     0x01    // No address mark

#define ATA_CMD_READ_PIO          0x20
#define ATA_CMD_READ_PIO_EXT      0x24
#define ATA_CMD_READ_DMA          0xC8
#define ATA_CMD_READ_DMA_EXT      0x25
#define ATA_CMD_WRITE_PIO         0x30
#define ATA_CMD_WRITE_PIO_EXT     0x34
#define ATA_CMD_WRITE_DMA         0xCA
#define ATA_CMD_WRITE_DMA_EXT     0x35
#define ATA_CMD_CACHE_FLUSH       0xE7
#define ATA_CMD_CACHE_FLUSH_EXT   0xEA
#define ATA_CMD_PACKET            0xA0
#define ATA_CMD_IDENTIFY_PACKET   0xA1
#define ATA_CMD_IDENTIFY          0xEC

#define      ATAPI_CMD_READ       0xA8
#define      ATAPI_CMD_EJECT      0x1B

#define ATA_IDENT_DEVICETYPE   0
#define ATA_IDENT_CYLINDERS    2
#define ATA_IDENT_HEADS        6
#define ATA_IDENT_SECTORS      12
#define ATA_IDENT_SERIAL       20
#define ATA_IDENT_MODEL        54
#define ATA_IDENT_CAPABILITIES 98
#define ATA_IDENT_FIELDVALID   106
#define ATA_IDENT_MAX_LBA      120
#define ATA_IDENT_COMMANDSETS  164
#define ATA_IDENT_MAX_LBA_EXT  200

#define ATA_REG_DATA       0x00
#define ATA_REG_ERROR      0x01
#define ATA_REG_FEATURES   0x01
#define ATA_REG_SECCOUNT0  0x02
#define ATA_REG_LBA0       0x03
#define ATA_REG_LBA1       0x04
#define ATA_REG_LBA2       0x05
#define ATA_REG_HDDEVSEL   0x06
#define ATA_REG_COMMAND    0x07
#define ATA_REG_STATUS     0x07
#define ATA_REG_SECCOUNT1  0x08
#define ATA_REG_LBA3       0x09
#define ATA_REG_LBA4       0x0A
#define ATA_REG_LBA5       0x0B
#define ATA_REG_CONTROL    0x0C
#define ATA_REG_ALTSTATUS  0x0C

#define ATA_TYPE_INVALID 0x0000
#define ATA_TYPE_PATA 0x0001
#define ATA_TYPE_SATA 0xC33C
#define ATA_TYPE_PATAPI 0xEB14
#define ATA_TYPE_SATAPI 0x9669

#define ATA_MASTER     0x00
#define ATA_SLAVE      0x01

// Channels:
#define      ATA_PRIMARY      0x00
#define      ATA_SECONDARY    0x01

// Directions:
#define      ATA_READ      0x00
#define      ATA_WRITE     0x01

typedef struct {
    u2 master_type;
    u2 slave_type;
    bool master_lba48;
    bool slave_lba48;
    u2 base;
    u2 control;
    u2 bus_master;
    u1 no_interrupt;
    u1 channel;
} Channel;
Channel channels[2];

static inline u2 reg_to_port(Channel * c, u1 reg) {
    u2 port = 0xFFFF;
    if (reg < 0x08) port = c->base + reg;
    else if (reg < 0x0C) port = c->base + reg - 0x6;
    else if (reg < 0x0E) port = c->control + reg - 0xA;
    else if (reg < 0x16) port = c->bus_master + reg - 0xE;
    return port;
}

void ata_write(u1 channel, u1 reg, u1 data);

static inline void prething(Channel * c, u1 reg) {
    if (reg >= 0x08 && reg < 0x0C)
        ata_write(c->channel, ATA_REG_CONTROL, c->no_interrupt | 0x80);
}

static inline void postthing(Channel * c, u1 reg) {
    if (reg >= 0x08 && reg < 0x0C)
        ata_write(c->channel, ATA_REG_CONTROL, c->no_interrupt);
}

void ata_write(u1 channel, u1 reg, u1 data) {
    Channel * c = &channels[channel];
    prething(c, reg);
    out1(reg_to_port(c, reg), data);
    postthing(c, reg);
}

u1 ata_read(u1 channel, u1 reg) {
    u1 result;
    Channel * c = &channels[channel];
    prething(c, reg);
    result = in1(reg_to_port(c, reg));
    postthing(c, reg);
    return result;
}

#define ATA_BUFFER_SIZE 128
u1 ata_buffer[ATA_BUFFER_SIZE];

void ata_read_buffer(u1 channel, u1 reg) {
    Channel * c = &channels[channel];

    prething(c, reg);
    insl(reg_to_port(c, reg), ata_buffer, ATA_BUFFER_SIZE);
    postthing(c, reg);
}

typedef enum {
    POLL_SUCCESS,
    POLL_ERROR,
    POLL_FAULT,
    POLL_DRQ
} ata_poll_result_t ;
ata_poll_result_t ata_poll(u1 channel, bool post_check) {
    for (u1 i = 0; i < 4; i++)
        ata_read(channel, ATA_REG_ALTSTATUS);

    while (ata_read(channel, ATA_REG_STATUS) & ATA_SR_BUSY) {};

    if (post_check) {
        u1 state = ata_read(channel, ATA_REG_STATUS);
        if (state & ATA_SR_ERR)
            return POLL_ERROR;
        else if (state & ATA_SR_DF)
            return POLL_FAULT;
        else if (!(state & ATA_SR_DRQ))
            return POLL_DRQ;
    }

    return POLL_SUCCESS;
}

#include "print.h"

void ata_initialize_controller(u1 bus, u1 device, u1 function) {
    u4 bar0 = pci_read_config4(bus, device, function, 0x10);
    u4 bar1 = pci_read_config4(bus, device, function, 0x14);
    u4 bar2 = pci_read_config4(bus, device, function, 0x18);
    u4 bar3 = pci_read_config4(bus, device, function, 0x1C);
    u4 bar4 = pci_read_config4(bus, device, function, 0x20);

#define PORT(BAR, DEFAULT) (((BAR) == 0 || (BAR) == 1) ? (DEFAULT) : (BAR))
#define BYTE_MASK(VALUE) ((VALUE) & 0xFFFFFFFC)
    channels[ATA_PRIMARY].channel = ATA_PRIMARY;
    channels[ATA_PRIMARY].base =
        PORT(bar0, ATA_LEGACY_PRIMARY_CHANNEL_BASE);
    channels[ATA_PRIMARY].control =
        PORT(bar1, ATA_LEGACY_PRIMARY_CHANNEL_CONTROL);
    channels[ATA_PRIMARY].bus_master = BYTE_MASK(bar4);
    channels[ATA_PRIMARY].no_interrupt = 1;

    channels[ATA_SECONDARY].channel = ATA_SECONDARY;
    channels[ATA_SECONDARY].base =
        PORT(bar2, ATA_LEGACY_SECONDARY_CHANNEL_CONTROL);
    channels[ATA_SECONDARY].control =
        PORT(bar3, ATA_LEGACY_SECONDARY_CHANNEL_CONTROL);
    channels[ATA_SECONDARY].bus_master = BYTE_MASK(bar4) + 8;
    channels[ATA_SECONDARY].no_interrupt = 1;

    /*
    print_format(
        "channels[ATA_PRIMARY].base = {x}\n"
        "channels[ATA_PRIMARY].control = {x}\n"
        "channels[ATA_SECONDARY].base = {x}\n"
        "channels[ATA_SECONDARY].control = {x}\n",
        channels[ATA_PRIMARY].base,
        channels[ATA_PRIMARY].control,
        channels[ATA_SECONDARY].base,
        channels[ATA_SECONDARY].control
        );
    */

    ata_write(ATA_PRIMARY, ATA_REG_CONTROL, 2);
    ata_write(ATA_SECONDARY, ATA_REG_CONTROL, 2);

    for (u1 i = 0; i < 2; i++) for (u1 j = 0; j < 2; j++) {
        u2 * type = j ? &channels[i].slave_type : &channels[i].master_type;
        bool * lba48 = j ? &channels[i].slave_lba48 : &channels[i].master_lba48;
        ata_write(i, ATA_REG_HDDEVSEL, 0xA0 | (j << 4));
        wait(2);
        ata_write(i, ATA_REG_COMMAND, ATA_CMD_IDENTIFY);
        wait(2);
        print_format("    ATA {s} {s}: ", i ? "Secondary" : "Primary", j ? "Slave" : "Master");
        if (!ata_read(i, ATA_REG_STATUS)) {
            print_string("Missing\n");
            *type = ATA_TYPE_INVALID;
            continue;
        }

        // "Error" Flag, is expected for PATAPI, SATA, and SATAPI
        bool error = false;
        u4 timeout = 1000;
        while (timeout) {
            u1 status = ata_read(i, ATA_REG_STATUS);
            if (status & ATA_SR_ERR) {
                error = true;
                break;
            } else if (!(status & ATA_SR_BUSY) && (status & ATA_SR_DRQ))
                break;
            timeout--;
        }
        if (!timeout) {
            print_string("Drive Timedout!\n");
            *type = ATA_TYPE_INVALID;
            continue;
        }

        if (error) {
            u1 lba1 = ata_read(i, ATA_REG_LBA1);
            u1 lba2 = ata_read(i, ATA_REG_LBA2);
            *type = (lba2 << 8) | lba1;
            switch (*type) {
            case ATA_TYPE_SATA:
                print_string("SATA\n");
                break;
            case ATA_TYPE_PATAPI:
                print_string("PATAPI\n");
                break;
            case ATA_TYPE_SATAPI:
                print_string("SATAPI\n");
                break;
            default:
                print_format("Unknown ATA Type {x}\n", *type);
                *type = ATA_TYPE_INVALID;
                continue;
            }

            ata_write(i, ATA_REG_COMMAND, ATA_CMD_IDENTIFY_PACKET);
            wait(2);
        } else {
            print_string("PATA\n");
            *type = ATA_TYPE_PATA;
        }

        ata_read_buffer(i, ATA_REG_DATA);

        char model_string[40];
        for (u1 i = 0; i < 40; i += 2) {
            model_string[i] = ata_buffer[ATA_IDENT_MODEL + i + 1];
            model_string[i + 1] = ata_buffer[ATA_IDENT_MODEL + i];
        }
        model_string[40] = '\0';
        print_format("        Name: \"{s}\"\n", model_string);

        u4 command_sets = *((u4*)&ata_buffer[ATA_IDENT_COMMANDSETS]);
        u4 size = 0;
        if (command_sets & (1 << 26)) {
            size = *((u4*)&ata_buffer[ATA_IDENT_MAX_LBA_EXT]);
            *lba48 = true;
        } else {
            size = *((u4*)&ata_buffer[ATA_IDENT_MAX_LBA]);
            *lba48 = false;
        }
        size *= BLOCK_SIZE;
        print_format("        {d} B\n", size);
        u4 kib_size = size >> 10;
        if (kib_size) {
            print_format("        {d} KiB\n", kib_size);
            u4 mib_size = kib_size >> 10;
            if (mib_size) {
                print_format("        {d} MiB\n", mib_size);
                u4 gib_size = mib_size >> 10;
                if (gib_size) {
                    print_format("        {d} GiB\n", gib_size);
                }
            }
        }
    }
}

void ata_read_disk(u4 sector, mem_t dest) {
    out1(0x01F6, sector >> 24 | 0xE0);
    out1(0x01F2, 1);
    out1(0x01F3, sector);
    out1(0x01F4, sector >> 8);
    out1(0x01F5, sector >> 16);
    out1(0x01F7, ATA_CMD_READ_PIO);
    print_string("About to Poll\n");
    wait(2);
    print_string("Poll Done, Reading\n");
    insw(0x1F0, (void*) dest, sector);
    print_string("Reading Done\n");
}
