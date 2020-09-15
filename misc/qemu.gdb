symbol-file tmp/iso/boot/kernel.elf
set disassemble-next-line on
set confirm off
set pagination off
set logging file tmp/gdb.log
set logging overwrite on
set logging on

break panic
# break platform.interrupts.BaseInterruptHandler(14,false,false).handler

target remote | qemu-system-i386 \
    -S -gdb stdio \
    -m 32 \
    -vga std \
    -cdrom georgios.iso \
    -serial file:tmp/serial.log \
    -boot order=dc \
    -no-reboot \
    -D tmp/qemu.log \
    -d int,cpu_reset,guest_errors \
    hd.img

#    -trace 'ide_*' \
#    -trace '*irq*' \
#    -trace '*apic*' \

continue
