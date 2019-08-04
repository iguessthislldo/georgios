ISO:=georgios.iso

ISO_DIR:=tmp/iso
ISO_BOOT_DIR=$(ISO_DIR)/boot
KERNEL:=$(ISO_BOOT_DIR)/kernel.elf
GRUB_CFG:=$(ISO_BOOT_DIR)/grub/grub.cfg

CC:=i686-elf-gcc
DEBUGGER:=i686-elf-gdb
CFLAGS:=-std=gnu11 -O0 -g -ffreestanding -nostdlib -pedantic -Wall -Wextra -Wno-pointer-arith

all: $(ISO) tmp/programs/test_prog/test_prog.elf

$(GRUB_CFG): misc/grub.cfg
	@mkdir -p $(dir $@)
	cp $< $(GRUB_CFG)

$(ISO): $(KERNEL) $(GRUB_CFG)
	grub-mkrescue --output=$(ISO) $(ISO_DIR)

hd.img: tmp/programs/test_prog/test_prog.elf
	python3 scripts/create_hd_img.py 512 $< $@

$(KERNEL): kernel/platform/linking.ld FORCE
	@mkdir -p $(dir $@)
	zig build --cache-dir tmp/zig-cache
	cp tmp/zig-cache/bin/kernel.elf $(KERNEL)
	grub-file --is-x86-multiboot2 $(KERNEL)
	objdump -S $(KERNEL) > tmp/annotated_kernel
FORCE:

tmp/programs/test_prog/test_prog.elf: programs/test_prog/test_prog.ld programs/test_prog/test_prog.s
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -T $^ -o $@

.PHONY: bochs
bochs:
	bochs -q -f misc/bochs_config -rc misc/bochs_rc

.PHONY: qemu
qemu: hd.img
	$(DEBUGGER) -x misc/qemu.gdb

.PHONY: clean
clean:
	rm -fr tmp $(ISO) hd.img
