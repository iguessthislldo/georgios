source_directories:=src src/arch/x86_32 src/library
c_sources:=$(foreach directory, $(source_directories), $(wildcard $(directory)/*.c))
s_sources:=$(foreach directory, $(source_directories), $(wildcard $(directory)/*.s))
objects:=$(foreach object, $(c_sources:.c=.o) $(s_sources:.s=.o), tmp/$(object))
VPATH:=src:src/x86_32

KERNEL:=tmp/iso/boot/kernel
ISO:=os.iso
GRUB:=tmp/iso/boot/grub/stage2_eltorito

CC:=i686-elf-gcc
CFLAGS:=-ffreestanding -O2 -g -nostdlib -std=gnu99 -I src/library

AS:=i686-elf-as
ASFLAGS:=
# -am to see marco expansion

all: $(ISO)

$(GRUB):
	@mkdir -p tmp/iso/boot/grub
	curl -L -o $(GRUB) 'http://littleosbook.github.com/files/stage2_eltorito'
	cp misc/menu.lst tmp/iso/boot/grub

$(ISO): $(KERNEL) $(GRUB)
	genisoimage \
		-R                              \
		-b boot/grub/stage2_eltorito    \
		-no-emul-boot                   \
		-boot-load-size 4               \
		-A os                           \
		-input-charset utf8             \
		-quiet                          \
		-boot-info-table                \
		-o $@                       \
		tmp/iso

tmp/%.o: %.s
	@mkdir -p $(dir $@)
	$(AS) $(ASFLAGS) $< -o $@

tmp/%.o : %.c
	@mkdir -p $(dir $@)
	$(CC) -Wa,--32 -std=gnu99 $(CFLAGS) -Wall -Wextra -c $< -o $@

$(KERNEL): linking.ld $(objects)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -T $^ -o $@

.PHONY: run
run:
	bochs -q -f misc/bochs_config -rc misc/bochs_rc

.PHONY: clean
clean:
	rm -fr $(ISO) tmp
