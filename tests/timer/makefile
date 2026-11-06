ASM = timer.asm
BIN = timer.com
NASM_FLAGS = -O0
QEMU ?= qemu-system-i386

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

timerint.com: timerint.asm
	nasm $(NASM_FLAGS) -f bin -o timerint.com timerint.asm

irqcheck.com: irqcheck.asm
	nasm $(NASM_FLAGS) -f bin -o irqcheck.com irqcheck.asm
