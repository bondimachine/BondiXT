# makefile.mak

ASM = directserialboot.asm
BIN = directserialboot.bin
NASM_FLAGS = -O0

all: $(BIN)

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -drive file=$(BIN),format=raw -serial stdio