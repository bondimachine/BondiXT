# makefile.mak

ASM = bios.asm
BIN = bios.bin
NASM_FLAGS = -O0
QEMU ?= qemu-system-i386
QEMU_BIN = bios.qemu.bin
SRCS = $(ASM) serial.asm serial_util.asm video_serial.asm keyboard_serial.asm disk_embedded.asm config.serial.inc video_custom.asm mouse.asm timer.asm
# isapc: no PAM, so C0000 is plain RAM. No SeaBIOS runs under -bios, so put QEMU's VGA BIOS at C000:0000 ourselves (see video_custom.asm)
VGABIOS ?= $(firstword $(wildcard $(dir $(shell which $(QEMU)))../share/qemu/vgabios.bin /usr/share/qemu/vgabios.bin /usr/share/seabios/vgabios.bin))
QEMU_ARGS = -M isapc -bios rom.bin -serial stdio -device isa-vga -device loader,file=$(VGABIOS),addr=0xc0000,force-raw=on

all: $(BIN) $(BIN).elf

# QEMU image, built with -DQEMU
rom: $(QEMU_BIN) disk.bin
	# Bottom 4kb
	dd if=$(QEMU_BIN) of=$(QEMU_BIN).truncated bs=1 skip=61440 
	cp disk.bin disk.bin.truncated
	# at least QEMU doesn't like images bigger than 128kb 
	truncate -s 124kb disk.bin.truncated
	cat disk.bin.truncated $(QEMU_BIN).truncated > rom.bin


rom8k: $(BIN) disk.bin
	# Bottom 4kb
	dd if=$(BIN) of=$(BIN).truncated bs=1 skip=61440 
	cp disk.bin disk.bin.truncated
	truncate -s 4kb disk.bin.truncated
	touch empty.bin
	truncate -s 120kb empty.bin
	cat disk.bin.truncated $(BIN).truncated > rom8k.bin
	cat empty.bin disk.bin.truncated $(BIN).truncated > rom8k.bin.extended
	

$(BIN): $(SRCS)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(QEMU_BIN): $(SRCS)
	nasm $(NASM_FLAGS) -DQEMU -f bin -o $(QEMU_BIN) $(ASM)

$(BIN).elf: rom
	nasm $(NASM_FLAGS) -DQEMU -f elf32 -g -o $(BIN).elf $(ASM)


clean:
	rm -f $(BIN) $(BIN).elf $(BIN).truncated $(QEMU_BIN) $(QEMU_BIN).truncated rom.bin


# -device isa-debugcon,iobase=0x80,chardev=debug -chardev file,id=debug,path=/dev/stderr
run: rom
	$(QEMU) $(QEMU_ARGS)

run8k: rom8k
	$(QEMU) -M isapc -bios rom8k.bin.extended -serial stdio -device isa-vga 


debug: $(BIN).elf
	$(QEMU) $(QEMU_ARGS) -s -S