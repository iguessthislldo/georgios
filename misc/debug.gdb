symbol-file tmp/iso/boot/kernel
#display/4i $pc
#break *0x0
#break ps2.c:73
#break ps2_send
break boot.s: 
target remote | qemu-system-i386 -S -gdb stdio -m 16 -cdrom os.iso
continue
