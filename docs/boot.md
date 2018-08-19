# Boot

## Boot Loader

Georgios relies on GRUB for setting up the Multiboot structure, loading the
kernel, and getting the computer to go to `_start`.

*NOTE: `_start` is defined in boot.s and is declared as the entry point in
linking.ld.*

## `_start`

`_start` is the first phase of kernel initialization. It is completely written
in assembly and does the following:
- Move the pointer to the multiboot structure from `%eax` where GRUB left it
  to the place in memory where `platform_init()` will take it as its argument.
- In one continuous motion:
    - Set the Page Table so that kernel data and code (currently starting at
      0x00100000) can also be read and written starting at 0xC0100000, called
      a higher kernel.
    - Enabled Paging
    - Jump to the higher kernel
    - Disable the lower kernel memory range.
- Set up the Stack
- Call `platform_init()` and `kernel_main()`

## `platform_init()`

`platform_init()` is the second phase of kernel initialization. It is mostly
written in C and does the following:
- Set up the IBM PC basic text graphics mode.
- Set up low level structures like the GDT and IDT.
- Initialize various hardware related tasks specific to PCs.
- Converts Multiboot information so that the kernel can use when governing the
  computer.

## `kernel_main()`

`kernel_main()` is the third phase of kernel initialization. It is meant to be
platform independent. Currently it just sets up memory to be allocated as
needed by programs. In the future it will initialize higher level kernel
services, like the scheduler. It will then jump into the schedule
loop and start processes.
