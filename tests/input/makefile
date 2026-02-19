# makefile.mak

ASM = mouseboot.asm
BIN = mouseboot.bin
NASM_FLAGS = -O0

all: $(BIN)

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -fda $(BIN)