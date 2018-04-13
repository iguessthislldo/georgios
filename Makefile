rwildcard=$(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))

c_sources:=$(call rwildcard, src/, *.c)
s_sources:=$(call rwildcard, src/, *.s)
objects:=$(foreach object, $(c_sources:.c=.o) $(s_sources:.s=.o), tmp/$(object))

ISO:=os.iso

ISO_DIR:=tmp/iso
BOOT_DIR=boot
ISO_BOOT_DIR=$(ISO_DIR)/$(BOOT_DIR)
KERNEL:=$(ISO_BOOT_DIR)/kernel

GRUB:=$(BOOT_DIR)/grub
GRUB_BIN:=$(GRUB)/stage2_eltorito
GRUB_BIN_URL=http://littleosbook.github.com/files/stage2_eltorito
#GRUB_BIN_CHECKSUM:=b18ff4d5d923c4a190fea4d0313deebd
ISO_GRUB:=$(ISO_DIR)/$(GRUB)
ISO_GRUB_BIN:=$(ISO_DIR)/$(GRUB_BIN)

CC:=i686-elf-gcc
CFLAGS:=-ffreestanding -O2 -g -nostdlib -std=gnu11 -pedantic -Wno-pointer-arith -I src/platform -I src

AS:=i686-elf-as
ASFLAGS:=
# -am to see marco expansion

all: $(ISO)

$(ISO_GRUB):
	@mkdir -p $(ISO_GRUB)
	curl -L -o $(ISO_GRUB_BIN) '$(GRUB_BIN_URL)'
	#md5sum $(ISO_GRUB_BIN) | grep '$(GRUB_BIN_CHECKSUM)  '
	cp misc/menu.lst $(ISO_GRUB)

$(ISO): $(KERNEL) $(ISO_GRUB)
	genisoimage \
		-R                              \
		-b $(GRUB_BIN)    \
		-no-emul-boot                   \
		-boot-load-size 4               \
		-A os                           \
		-input-charset utf8             \
		-quiet                          \
		-boot-info-table                \
		-o $@                       \
		$(ISO_DIR)

tmp/%.o: %.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

tmp/%.o : %.c
	@mkdir -p $(dir $@)
	$(CC) -Wa,--32 $(CFLAGS) -Wall -Wextra -c $< -o $@

$(KERNEL): linking.ld $(objects)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -T $^ -o $@
	objdump -S $(KERNEL) > tmp/annotated_kernel

.PHONY: run
run:
	bochs -q -f misc/bochs_config -rc misc/bochs_rc

.PHONY: clean_all
clean_all:
	rm -fr tmp $(ISO)

# Remove everything except the grub files
tmploc:=/tmp/grub_tmp_copy_ee5f01ca-d372-4321-b330-68b076f0d29f
.PHONY: clean
clean:
	rm -fr $(tmploc)
	mv $(ISO_GRUB) $(tmploc)
	rm -fr tmp $(ISO)
	mkdir -p $(ISO_BOOT_DIR)
	mv $(tmploc) $(ISO_GRUB)

