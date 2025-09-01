# makefile.mak

ASM = hello.asm
BIN = hello.bin
NASM_FLAGS = -O0

all: $(BIN) $(BIN).dbg

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN).dbg: $(ASM)
	nasm $(NASM_FLAGS) -f elf32 -g -o $(BIN).dbg $(ASM)


clean:
	rm -f $(BIN)
