ENTRY(main_wrapper)

SECTIONS {
	.text : ALIGN(4K)
	{
		*(.text)
	}
}
