ENTRY(_start)

_PAGE_SIZE = 4K;

SECTIONS {
    /* space for a null and friends to trigger protection */
    . = ALIGN(1M);

    .text : ALIGN(_PAGE_SIZE)
    {
        *(.text)
    }

    .data : ALIGN(_PAGE_SIZE)
    {
        *(.data)
    }

    .bss : ALIGN(_PAGE_SIZE)
    {
        *(.bss)
        *(COMMON)
    }

    _end = ALIGN(_PAGE_SIZE);
}
