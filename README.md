# Unnamed Hobby Operating System

My OS that I'm making for fun which currently targets i386/IA-32. Hopefully I
will be able to target x86\_64/AMD64 in the future. The purposes of this OS are
to serve as a learning experience and as an experiment with a OS built around a
[tag](https://en.wikipedia.org/wiki/Tag_\(metadata\)) based file system. My
plans for how this part will work are not yet concrete as I hope to work on
that once the possible of implementing a file system comes into view.

## Resources Used

- [OS Dev Wiki](http://wiki.osdev.org/)
    - Very popular, fairly large set of resources in one place, but rough
      or just plain unhelpful in many places.
- [The little book about OS development](https://littleosbook.github.io/)
    - Polished, but limited intro into x86 OS development. Provided me with
      the initial start.
- [Intel x86 Software Development Mannuals](https://software.intel.com/en-us/articles/intel-sdm)
- [The Design and Implementation of the 4.4 BSD Operating System](https://www.amazon.com/Implementation-Operating-paperback-Addison-wesley-Systems/dp/0132317923)

## Tasks

### Currently Done

- Getting to a kernel written in C from GRUB.
- Basic Interrupts (like divide by zero) can be handled.
- Printing to the screen in Real Mode graphics including a printf like
  function.
- [Higher Half Kernel](http://wiki.osdev.org/Higher\_Half\_Kernel)

### In Progress

- malloc/free functionality
- Time related functions like timer interrupts.

### Future

- Basic File System
- Userspace and Processes!
- Tag Based File System
- Graphics?

