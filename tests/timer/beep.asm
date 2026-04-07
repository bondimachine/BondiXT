CPU 8086
org 0x100


start:

    call beep
    mov ah, 0x4C
    int 0x21


%include "../../bios/timer.asm"


