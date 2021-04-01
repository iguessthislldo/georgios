# Georgios

![Saint George and the Dragon](misc/george_and_dragon.png)

"ST. GEORGE OF MERRIE ENGLAND" Illustration by Arthur Rackham for 1927 "English
Fairy Tales" by Flora Annie Webster Steel, [File
Source](http://www.publicdomainfiles.com/show_file.php?id=13550814618613)

Georgios (Greek for George, said like *GORE-GEE-OS*) is an operating system I'm
making for fun which currently targets i386/IA-32. The purpose of this project
is to serve as a learning experience.

This OS is not anywhere near usable and currently will just run whatever I'm
working on.

## Building

Building Georgios requires a Unix-like environment with:
- [Zig](https://ziglang.org/)
  - Currently using 0.7.1
- GRUB2
  - Requires i686 Support (`grub-pc-bin` package on Ubuntu)

Georgios can be built as a bootable ISO (called `georgios.iso`) by running
`make`. If installed, QEMU and Bochs can be run by running `make qemu` or `make
bochs` respectively.  For the moment it assumes the existence of an IDE disk
with certain files on it.

## Resources Used

- [OSDev Wiki](http://wiki.osdev.org/)
    - Very popular, fairly large set of resources in one place, but rough
      or just plain unhelpful in many places.
- [The little book about OS development](https://littleosbook.github.io/)
    - Polished, but limited intro into x86 OS development. Provided me with
      the initial start.
- [Intel x86 Software Development Manuals](https://software.intel.com/en-us/articles/intel-sdm)
- [xv6](https://github.com/mit-pdos/xv6-public)
- [The Design and Implementation of the 4.4 BSD Operating System](https://www.amazon.com/Implementation-Operating-paperback-Addison-wesley-Systems/dp/0132317923)
- [FYSOS: Media Storage Devices](https://www.amazon.com/dp/1514111888/)
