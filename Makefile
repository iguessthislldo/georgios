rwildcard=$(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))

c_sources:=$(call rwildcard, kernel/, *.c)
s_sources:=$(call rwildcard, kernel/, *.s)
objects:=$(foreach object, $(c_sources:.c=.o) $(s_sources:.s=.o), tmp/$(object))
depends:=$(foreach depend, $(c_sources:.c=.d), tmp/$(depend))

ISO:=georgios.iso

ISO_DIR:=tmp/iso
ISO_BOOT_DIR=$(ISO_DIR)/boot
KERNEL:=$(ISO_BOOT_DIR)/kernel
GRUB_CFG:=$(ISO_BOOT_DIR)/grub/grub.cfg

ifdef BOOT_TEST
BOOT_TEST:=-DBOOT_TEST
else
BOOT_TEST:=
endif

CC:=i686-elf-gcc
DEBUGGER:=i686-elf-gdb
CFLAGS:=-std=gnu11 -O0 -g -ffreestanding -nostdlib -pedantic -Wall -Wextra -Wno-pointer-arith $(BOOT_TEST)
KERNEL_INCLUDES:=-Ikernel/platform -Itmp/kernel/platform -Ikernel -Itmp/kernel

AS:=i686-elf-as
ASFLAGS:=
# -am to see marco expansion

all: $(ISO) tmp/programs/test_prog/test_prog.elf

.PHONY: depend
depend: $(depends)

$(GRUB_CFG): misc/grub.cfg
	@mkdir -p $(dir $@)
	cp $< $(GRUB_CFG)

$(ISO): $(KERNEL) $(GRUB_CFG)
	grub-mkrescue --output=$(ISO) $(ISO_DIR)

tmp/%.o: %.s
	@mkdir -p $(dir $@)
	$(CC) -Wa,--32 -c -x assembler-with-cpp $(CFLAGS) $< -o $@

tmp/%.o : %.c
	@mkdir -p $(dir $@)
	$(CC) -Wa,--32 $(CFLAGS) $(KERNEL_INCLUDES) -c $< -o $@

tmp/%.d: %.c
	@mkdir -p $(dir $@)
	@set -e; rm -f $@; \
	 $(CC) -M $(CFLAGS) $(KERNEL_INCLUDES) $< > $@.$$$$; \
	 sed 's,\($*\)\.o[ :]*,\1.o $@ : ,g' < $@.$$$$ > $@; \
	 rm -f $@.$$$$

hd.img:
	qemu-img create -f raw hd.img 100M

$(KERNEL): kernel/platform/linking.ld $(objects)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -T $^ -o $@
	grub-file --is-x86-multiboot2 $(KERNEL)
	objdump -S $(KERNEL) > tmp/annotated_kernel

.PHONY: bochs
bochs:
	bochs -q -f misc/bochs_config -rc misc/bochs_rc

tmp/programs/test_prog/test_prog.elf: programs/test_prog/test_prog.ld programs/test_prog/test_prog.s
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -T $^ -o $@

.PHONY: qemu
qemu: hd.img
	$(DEBUGGER) -x misc/qemu.gdb

.PHONY: clean
clean:
	rm -fr tmp $(ISO) hd.img
