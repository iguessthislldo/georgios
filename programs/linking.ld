ENTRY(_start)

SECTIONS {
	.text : ALIGN(4K)
	{
		*(.text)
	}
}
