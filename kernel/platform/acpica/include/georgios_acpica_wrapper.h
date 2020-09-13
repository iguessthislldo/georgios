#ifndef GEORGIOS_ACPICA_WRAPPER_HEADER
#define GEORGIOS_ACPICA_WRAPPER_HEADER

#include <acpi.h>

typedef UINT8 Uint8;
typedef UINT16 Uint16;
typedef UINT32 Uint32;
typedef UINT64 Uint64;

typedef ACPI_STATUS Status;
const Status Ok = AE_OK;
const Status Error = AE_ERROR;
const Status NoMemory = AE_NO_MEMORY;

typedef ACPI_SIZE Size;

typedef ACPI_PHYSICAL_ADDRESS PhysicalAddress;

#endif
