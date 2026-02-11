BITS 16

POST_PORT equ 0x378
times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

_start:

    mov cl, 1

_continue:

    mov dx, POST_PORT
    mov al, cl

    out dx, al

    mov bx, 0
_wait:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait; 16

    rol cl, 1
    jmp _continue

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp _start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0