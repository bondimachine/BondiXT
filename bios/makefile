# makefile.mak

ASM = bios.asm
BIN = bios.bin
NASM_FLAGS = -O0

all: $(BIN) $(BIN).elf

$(BIN): $(ASM) serial.asm video_serial.asm config.serial.inc
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN).elf: $(BIN)
	nasm $(NASM_FLAGS) -f elf32 -g -o $(BIN).elf $(ASM)


clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -bios $(BIN) -serial stdio

debug: $(BIN).elf
	qemu-system-i386 -bios $(BIN) -serial stdio	-s -S