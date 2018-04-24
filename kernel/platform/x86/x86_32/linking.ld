ENTRY(_start)

KERNEL_OFFSET = 0xC0000000;
KERNEL_LOW_START = 0x00100000;
KERNEL_HIGH_START = KERNEL_LOW_START + KERNEL_OFFSET;
KERNEL_SIZE = KERNEL_LOW_END - KERNEL_LOW_START;

SECTIONS {
    . = KERNEL_HIGH_START;

	.text
        ALIGN(4K) : AT(ADDR(.text) - KERNEL_OFFSET)
	{
		*(.multiboot)
		*(.text)
	}

	/* Read-only data. */
	.rodata ALIGN(4K) : AT(ADDR(.rodata) - KERNEL_OFFSET)
	{
		*(.rodata)
	}

	/* Read-write data (initialized) */
	.data ALIGN(4K) : AT(ADDR(.data) - KERNEL_OFFSET)
	{
		*(.data)
	}

	/* Read-write data (uninitialized) and stack */
	.bss ALIGN(4K) : AT(ADDR(.bss) - KERNEL_OFFSET)
	{
		*(COMMON)
		*(.bss)
	}

    /*
     * End of Kernel
     */
    KERNEL_HIGH_END = .;
    KERNEL_LOW_END = KERNEL_HIGH_END - KERNEL_OFFSET;
}
