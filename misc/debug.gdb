symbol-file tmp/iso/boot/kernel
display/4i $pc
#break kernel.c:82
target remote | qemu-system-i386 -S -gdb stdio -m 16 -cdrom os.iso
continue
