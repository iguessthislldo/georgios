ENTRY(_start)

_KERNEL_OFFSET = 0xC0000000;
_KERNEL_LOW_START = 0x00100000;
_KERNEL_HIGH_START = _KERNEL_LOW_START + _KERNEL_OFFSET;
_KERNEL_SIZE = _KERNEL_LOW_END - _KERNEL_LOW_START;

SECTIONS {
    . = _KERNEL_HIGH_START;

	.text
        ALIGN(4K) : AT(ADDR(.text) - _KERNEL_OFFSET)
	{
		*(.multiboot)
		*(.text)
	}

	/* Read-only data. */
	.rodata ALIGN(4K) : AT(ADDR(.rodata) - _KERNEL_OFFSET)
	{
		*(.rodata)
	}

	/* Read-write data (initialized) */
	.data ALIGN(4K) : AT(ADDR(.data) - _KERNEL_OFFSET)
	{
		*(.data)
	}

	/* Read-write data (uninitialized) and stack */
	.bss ALIGN(4K) : AT(ADDR(.bss) - _KERNEL_OFFSET)
	{
		*(COMMON)
		*(.bss)
	}

    /*
     * End of Kernel
     */
    _KERNEL_HIGH_END = .;
    _KERNEL_LOW_END = _KERNEL_HIGH_END - _KERNEL_OFFSET;
}
