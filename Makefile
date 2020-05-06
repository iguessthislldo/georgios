ISO:=georgios.iso

ISO_DIR:=tmp/iso
ISO_BOOT_DIR=$(ISO_DIR)/boot
KERNEL:=$(ISO_BOOT_DIR)/kernel.elf
ZIG_OUTPUT:=tmp/zig-cache/bin
GRUB_PREFIX:=/usr
GRUB_LOCATION:=$(GRUB_PREFIX)/lib/grub/i386-pc
GRUB_CFG:=$(ISO_BOOT_DIR)/grub/grub.cfg

DEBUGGER:=gdb

multiboot_vga_request?=false
debug_log?=true

all: $(ISO) hd.img

.PHONY: build_georgios
build_georgios:
	zig build \
		--cache-dir tmp/zig-cache \
		-Dmultiboot_vga_request=$(multiboot_vga_request) \
		-Ddebug_log=$(debug_log) \

.PHONY: test
test:
	zig test --cache-dir tmp/zig-cache kernel/test.zig

$(GRUB_CFG): misc/grub.cfg
	@mkdir -p $(dir $@)
	cp $< $(GRUB_CFG)

$(KERNEL): build_georgios
	@mkdir -p $(dir $@)
	cp $(ZIG_OUTPUT)/kernel.elf $(KERNEL)
	grub-file --is-x86-multiboot2 $(KERNEL)
	nm --print-size --numeric-sort tmp/iso/boot/kernel.elf | grep -v '__' > tmp/annotated_kernel
	objdump -S $(KERNEL) >> tmp/annotated_kernel

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
	rm -fr tmp $(ISO) hd.img zig-cache
