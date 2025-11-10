BITS 16

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

_start:

    mov cl, 1

_continue:

    mov dx, 0x378
    mov al, cl

    out dx, al

    ; this is only needed for QEMU to print on the screen
    ; mov dx, 0x37A
    ; mov al, 0x08 | 0x04 | 1 ; 0x08 = select 0x04 = !intialize and 1 = strobe
    ; out dx, al
    ; mov al, 0x08 | 0x04
    ; out dx, al

    mov bx, 0
_wait:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jl _wait; 16

    rol cl, 1
    jmp _continue

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp _start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0