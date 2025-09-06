# makefile.mak

ASM = directserialboot.asm
BIN = directserialboot.bin
ASM14 = int14hserialboot.asm
BIN14 = int14hserialboot.bin
NASM_FLAGS = -O0

all: $(BIN)

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN14): $(ASM14)
	nasm $(NASM_FLAGS) -f bin -o $(BIN14) $(ASM14)

clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -drive file=$(BIN),format=raw -serial stdio

run14: $(BIN14)
	qemu-system-i386 -drive file=$(BIN14),format=raw -serial stdio	