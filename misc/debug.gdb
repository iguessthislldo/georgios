symbol-file tmp/iso/boot/kernel
display/4i $pc
#break kernel_main
break kernel.c:87
#break *0x0
target remote | qemu-system-i386 -S -gdb stdio -m 16 -cdrom os.iso
