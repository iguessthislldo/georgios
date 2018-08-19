symbol-file tmp/iso/boot/kernel
set disassemble-next-line on
set confirm off
set pagination off
set logging file tmp/gdb.log
set logging overwrite on
set logging on

target remote | qemu-system-i386 -S -gdb stdio -m 16 -cdrom os.iso -serial file:tmp/serial.log
continue
