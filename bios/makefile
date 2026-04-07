# makefile.mak

ASM = bios.asm
BIN = bios.bin
NASM_FLAGS = -O0
QEMU ?= qemu-system-i386

all: $(BIN) $(BIN).elf

rom: $(BIN) disk.bin
	# Bottom 4kb
	dd if=$(BIN) of=$(BIN).truncated bs=1 skip=61440 
	cp disk.bin disk.bin.truncated
	# at least QEMU doesn't like images bigger than 128kb 
	truncate -s 124kb disk.bin.truncated
	cat disk.bin.truncated $(BIN).truncated > rom.bin


rom8k: $(BIN) disk.bin
	# Bottom 4kb
	dd if=$(BIN) of=$(BIN).truncated bs=1 skip=61440 
	cp disk.bin disk.bin.truncated
	truncate -s 4kb disk.bin.truncated
	touch empty.bin
	truncate -s 120kb empty.bin
	cat disk.bin.truncated $(BIN).truncated > rom8k.bin
	cat empty.bin disk.bin.truncated $(BIN).truncated > rom8k.bin.extended
	

$(BIN): $(ASM) serial.asm video_serial.asm keyboard_serial.asm disk_embedded.asm config.serial.inc video_custom.asm mouse.asm timer.asm
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN).elf: rom
	nasm $(NASM_FLAGS) -f elf32 -g -o $(BIN).elf $(ASM)


clean:
	rm -f $(BIN) $(BIN).elf $(BIN).truncated rom.bin


# -device isa-debugcon,iobase=0x80,chardev=debug -chardev file,id=debug,path=/dev/stderr
run: rom
	$(QEMU) -bios rom.bin -serial stdio -device isa-vga 

run8k: rom8k
	$(QEMU) -bios rom8k.bin.extended -serial stdio -device isa-vga 


debug: $(BIN).elf
	$(QEMU) -bios rom.bin -serial stdio -device isa-vga -s -S