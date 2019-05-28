#ifndef ATA_HEADER
#define ATA_HEADER

#include <library.h>
#include "platform.h"

void ata_initialize_controller(u1 bus, u1 device, u1 function);
bool ata_disk_read(u1 disk, u4 sector, mem_t dest);

#endif
