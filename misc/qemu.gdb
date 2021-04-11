symbol-file tmp/root/boot/kernel.elf
set disassemble-next-line on
set confirm off
set pagination off
set logging file tmp/gdb.log
set logging overwrite on
set logging on

break kernel.panic
# break platform.interrupts.BaseInterruptHandler(14,false,false).handler
# break usermode_iret

target remote | qemu-system-i386 \
    -S -gdb stdio \
    -m 32 \
    -vga std \
    -cdrom georgios.iso \
    -serial file:tmp/serial.log \
    -boot order=cd \
    -no-reboot \
    -D tmp/qemu.log \
    -d int,cpu_reset,guest_errors \
    -soundhw pcspk \
    disk.img

#    -trace 'ide_*' \
#    -trace '*irq*' \
#    -trace '*apic*' \

continue
