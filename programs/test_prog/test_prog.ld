ENTRY(test_prog_start)

SECTIONS {
	.text : ALIGN(4K)
	{
		*(.text)
	}
}
