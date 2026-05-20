# makefile.mak

ASM = keyint.asm
BIN = keyint.com
NASM_FLAGS = -O0

all: $(BIN)

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -drive file=$(BIN),format=raw -serial stdio