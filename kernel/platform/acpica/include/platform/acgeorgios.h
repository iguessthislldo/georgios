#ifndef GEORGIOS_ACPICA_CONFIG_HEADER
#define GEORGIOS_ACPICA_CONFIG_HEADER

#define ACPI_MACHINE_WIDTH 32

#define ACPI_DIV_64_BY_32(n_hi, n_lo, d32, q32, r32) \
    asm("divl %2;" : "=a"(q32), "=d"(r32) : "r"(d32), "0"(n_lo), "1"(n_hi))
#define ACPI_SHIFT_RIGHT_64(n_hi, n_lo) \
    asm("shrl $1, %2; rcrl $1, %3;" : "=r"(n_hi), "=r"(n_lo) : "0"(n_hi), "1"(n_lo))

#define ACPI_NO_ERROR_MESSAGES

#endif
