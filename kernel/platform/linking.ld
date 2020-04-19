ENTRY(kernel_start)

_KERNEL_REAL_START = 1M;

Gi = 1M * 1K;
_KERNEL_OFFSET = 3 * Gi;

_KERNEL_VIRTUAL_START = _KERNEL_REAL_START + _KERNEL_OFFSET;
_KERNEL_REAL_END = _KERNEL_VIRTUAL_END - _KERNEL_OFFSET;
_KERNEL_SIZE = _KERNEL_REAL_END - _KERNEL_REAL_START;

low_kernel_page_table = kernel_page_table - _KERNEL_OFFSET;
low_page_directory = page_directory - _KERNEL_OFFSET;
low_multiboot_info_pointer = multiboot_info_pointer - _KERNEL_OFFSET;

SECTIONS {
    /*
     * Start of the "low" kernel, which is mapped to < _KERNEL_OFFSET
     */
    . = _KERNEL_REAL_START;

    .low_text ALIGN(4K) :
    {
        *(.multiboot)
        *(.low_text)
    }

    .low_bss ALIGN(4K) :
    {
        *(.low_bss)
    }

    /*
     * Start of the "high" kernel, which is mapped to >= _KERNEL_OFFSET
     */
    . += _KERNEL_OFFSET;

    .text ALIGN(4K) : AT(ADDR(.text) - _KERNEL_OFFSET)
    {
        *(.text)
    }

    .rodata ALIGN(4K) : AT(ADDR(.rodata) - _KERNEL_OFFSET)
    {
        *(.rodata)
    }

    .data ALIGN(4K) : AT(ADDR(.data) - _KERNEL_OFFSET)
    {
        *(.data)
    }

    .bss ALIGN(4K) : AT(ADDR(.bss) - _KERNEL_OFFSET)
    {
        *(COMMON)
        *(.bss)
    }

    _KERNEL_VIRTUAL_END = .;
}
