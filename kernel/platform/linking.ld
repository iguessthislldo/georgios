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
low_page_directory = page_directory - _VIRTUAL_OFFSET;
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
        __debug_info_start = .;
        KEEP(*(.debug_info))
        __debug_info_end = .;
        __debug_abbrev_start = .;
        KEEP(*(.debug_abbrev))
        __debug_abbrev_end = .;
        __debug_str_start = .;
        KEEP(*(.debug_str))
        __debug_str_end = .;
        __debug_line_start = .;
        KEEP(*(.debug_line))
        __debug_line_end = .;
        __debug_ranges_start = .;
        KEEP(*(.debug_ranges))
        __debug_ranges_end = .;
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
