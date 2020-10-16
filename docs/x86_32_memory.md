# x86\_32 Memory

## Map of Real Memory

| Contents            | Start                    | End                  |
| ------------------- | ------------------------ | -------------------- |
| Available           | 0                        | ?                    |
| BIOS Area           | ?                        | `_KERNEL_REAL_START` |
| Kernel              | `_KERNEL_REAL_START`     | `_KERNEL_REAL_END`   |
| Multiboot Info      | `multiboot_info_pointer` | `kernel_page_tables` |
| Initial Page Tables | `kernel_page_tables`     | ?                    |
| Available           | ?                        | ?                    |

## Notes

- Kernel might have internal spaces that will be recycled as available frames after they
  are done being used.

- Multiboot Info will be copied from its original location in
  `kernel_main_wrapper` so we don't accidentally overwrite it. Its memory space
  will be page aligned so it can be recycled into frames when we are done with
  it.

- The initial page tables set up in `kernel_main_wrapper` will map the real
  memory from 0 to the end of the page table of the end of Multiboot Info.
  Until full memory management kicks in we shouldn't need to interact with any
  other range of memory.

## Resources

- http://ethv.net/workshops/osdev/notes/notes-2
    - Used linked list described there for the physical memory allocator.
