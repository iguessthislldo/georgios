#ifndef ATA_HEADER
#define ATA_HEADER

#include <basic_types.h>

void ata_initialize_controller(u1 bus, u1 device, u1 function);
bool ata_disk_read(u1 disk, u4 sector);

u1 ata_buffer[512];

#endif
