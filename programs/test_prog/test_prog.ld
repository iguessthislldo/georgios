ENTRY(main)

SECTIONS {
	.text : ALIGN(4K)
	{
		*(.text)
	}
}
