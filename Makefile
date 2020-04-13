ISO:=georgios.iso

ISO_DIR:=tmp/iso
ISO_BOOT_DIR=$(ISO_DIR)/boot
KERNEL:=$(ISO_BOOT_DIR)/kernel.elf
ZIG_OUTPUT:=tmp/zig-cache/bin
GRUB_PREFIX:=/usr
GRUB_LOCATION:=$(GRUB_PREFIX)/lib/grub/i386-pc
GRUB_CFG:=$(ISO_BOOT_DIR)/grub/grub.cfg
GRUB_MODULES:=vbe font gfxterm echo reboot usb_keyboard multiboot2 fat ls cat ext2 iso9660 reiserfs xfs part_sun part_gpt part_msdos video_bochs video_cirrus all_video

DEBUGGER:=gdb

all: $(ISO) hd.img

.PHONY: build_georgios
build_georgios:
	zig build --cache-dir tmp/zig-cache

.PHONY: test
test:
	zig test --cache-dir tmp/zig-cache kernel/util.zig
	zig test --cache-dir tmp/zig-cache kernel/io.zig

$(GRUB_CFG): misc/grub.cfg
	@mkdir -p $(dir $@)
	cp $< $(GRUB_CFG)

$(KERNEL): build_georgios
	@mkdir -p $(dir $@)
	cp $(ZIG_OUTPUT)/kernel.elf $(KERNEL)
	grub-file --is-x86-multiboot2 $(KERNEL)
	objdump -S $(KERNEL) > tmp/annotated_kernel

$(ISO): $(KERNEL) $(GRUB_CFG)
	cp $(GRUB_PREFIX)/share/grub/unicode.pf2 $(ISO_BOOT_DIR)/grub
	grub-mkrescue --directory=$(GRUB_LOCATION) --output=$(ISO) --modules="$(GRUB_MODULES)" $(ISO_DIR)

$(ZIG_OUTPUT)/test_prog.elf: build_georgios

hd.img: $(ZIG_OUTPUT)/test_prog.elf
	python3 scripts/create_hd_img.py 512 $< $@

.PHONY: bochs
bochs:
	bochs -q -f misc/bochs_config -rc misc/bochs_rc

.PHONY: qemu
qemu:
	$(DEBUGGER) -x misc/qemu.gdb

.PHONY: clean
clean:
	rm -fr tmp $(ISO) hd.img
