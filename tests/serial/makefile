# makefile.mak

ASM = directserialboot.asm
BIN = directserialboot.bin
ASM14 = int14hserialboot.asm
BIN14 = int14hserialboot.bin
BIOSASM = serialbios.asm
BIOSBIN = serialbios.bin
NASM_FLAGS = -O0

all: $(BIN)

$(BIN): $(ASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN14): $(ASM14)
	nasm $(NASM_FLAGS) -f bin -o $(BIN14) $(ASM14)

$(BIOSBIN): $(BIOSASM)
	nasm $(NASM_FLAGS) -f bin -o $(BIOSBIN) $(BIOSASM)
	# Bottom 8kb 
	dd if=$(BIOSBIN) of=$(BIOSBIN).truncated8k bs=1 skip=57344

clean:
	rm -f $(BIN)

run: $(BIN)
	qemu-system-i386 -drive file=$(BIN),format=raw -serial stdio

run14: $(BIN14)
	qemu-system-i386 -drive file=$(BIN14),format=raw -serial stdio	

runbios: $(BIOSBIN)
	qemu-system-i386 -bios $(BIOSBIN) -serial stdio -icount 0