/*
 * This file defines the layout of the kernel itself and allows the kernel to
 * access this information through symbols. The most important aspect of this
 * is the real vs virtual kernel. Very early in boot this maps the lower real
 * memory of the kernel into a much higher virtual address that becomes the
 * start of the kernel mode memory space. See
 * https://wiki.osdev.org/Higher_Half_Kernel for info.
 */

ENTRY(kernel_start)

/* Basic constants */
_REAL_START = 1M;
_VIRTUAL_OFFSET = 3 << 30; /* 3 Gi */
_FRAME_SIZE = 4K;

/* Derived Values */
_VIRTUAL_START = _REAL_START + _VIRTUAL_OFFSET;
_REAL_END = _VIRTUAL_END - _VIRTUAL_OFFSET;
_KERNEL_SIZE = _REAL_END - _REAL_START;
_VIRTUAL_LOW_START = _REAL_LOW_START + _VIRTUAL_OFFSET;
_VIRTUAL_LOW_END = _REAL_LOW_END + _VIRTUAL_OFFSET;

/* Create some low versions of symbols we need */
low_page_directory = active_page_directory - _VIRTUAL_OFFSET;
low_multiboot_info = multiboot_info - _VIRTUAL_OFFSET;
low_kernel_range_start_available =
    kernel_range_start_available - _VIRTUAL_OFFSET;
low_kernel_page_table_count = kernel_page_table_count - _VIRTUAL_OFFSET;
low_kernel_page_tables = kernel_page_tables - _VIRTUAL_OFFSET;

SECTIONS {
    /*
     * Start of the "low" kernel, which is mapped to < _VIRTUAL_OFFSET.
     * This memory will be recycled after it is no longer needed.
     */
    . = _REAL_START;
    _REAL_LOW_START = .;

    .low_text ALIGN(_FRAME_SIZE) :
    {
        *(.multiboot)
        *(.low_text)
    }

    .low_bss ALIGN(_FRAME_SIZE) :
    {
        *(.low_bss)
    }

    _REAL_LOW_END = .;

    /*
     * Start of the "high" kernel, which is mapped to >= _VIRTUAL_OFFSET.
     */
    . += _VIRTUAL_OFFSET;

    .text ALIGN(_FRAME_SIZE) : AT(ADDR(.text) - _VIRTUAL_OFFSET)
    {
        *(.text)
    }

    .rodata ALIGN(_FRAME_SIZE) : AT(ADDR(.rodata) - _VIRTUAL_OFFSET)
    {
        *(.rodata)
    }

    .data ALIGN(_FRAME_SIZE) : AT(ADDR(.data) - _VIRTUAL_OFFSET)
    {
        *(.data)
    }

    .bss ALIGN(_FRAME_SIZE) : AT(ADDR(.bss) - _VIRTUAL_OFFSET)
    {
        *(COMMON)
        *(.bss)
    }

    _VIRTUAL_END = .;
}
