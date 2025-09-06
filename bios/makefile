# makefile.mak

ASM = bios.asm
BIN = bios.bin
NASM_FLAGS = -O0

all: $(BIN) $(BIN).elf

rom: $(BIN)
	# Bottom 4kb
	dd if=$(BIN) of=$(BIN).truncated bs=1 skip=61440 
	cp disk.bin disk.bin.truncated
	# at least QEMU doesn't like images bigger than 128kb 
	truncate -s 124kb disk.bin.truncated
	cat disk.bin.truncated $(BIN).truncated > rom.bin

$(BIN): $(ASM) serial.asm video_serial.asm keyboard_serial.asm disk_embedded.asm config.serial.inc
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN).elf: $(BIN)
	nasm $(NASM_FLAGS) -f elf32 -g -o $(BIN).elf $(ASM)


clean:
	rm -f $(BIN) $(BIN).elf $(BIN).truncated rom.bin

run: rom
	qemu-system-i386 -bios rom.bin -serial stdio

debug: $(BIN).elf
	qemu-system-i386 -bios rom.bin -serial stdio -s -S