# makefile.mak

ASM = ledtest.asm
BIN = ledtest.bin
NASM_FLAGS = -O0
QEMU ?= qemu-system-i386

all: $(BIN) $(BIN).elf

rom: $(BIN)
	# Bottom 32kb
	dd if=$(BIN) of=$(BIN).truncated bs=1 skip=32768
	# Bottom 8kb 
	dd if=$(BIN) of=$(BIN).truncated8k bs=1 skip=57344
	# 128kb
	dd if=/dev/zero of=$(BIN).truncated128k bs=1 count=65536
	cat $(BIN) >> $(BIN).truncated128k

$(BIN): $(ASM) ledtest.asm
	nasm $(NASM_FLAGS) -f bin -o $(BIN) $(ASM)

$(BIN).elf: rom
	nasm $(NASM_FLAGS) -f elf32 -g -o $(BIN).elf $(ASM)

clean:
	rm -f $(BIN) $(BIN).elf $(BIN).truncated $(BIN).truncated8k	$(BIN).truncated128k

run: rom
	$(QEMU) -bios $(BIN) -icount shift=10 -device isa-debugcon,iobase=0x80,chardev=debug -chardev stdio,id=debug,mux=on | xxd -p -c 1

debug: $(BIN).elf
	$(QEMU) -bios $(BIN) -device isa-debugcon,iobase=0x80,chardev=debug -chardev stdio,id=debug,mux=on -s -S