BITS 16

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

start:
    
    mov ax, cs
    mov ds, ax
    mov es, ax


    call serial_init

    mov dx, 0x378
    mov al, 0b11000011
    out dx, al

continue:    

    mov dx, 0x3F8

    mov al, 'H'
    out dx, al

    mov bx, 0
_wait0:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait0; 16

    mov al, 'o'
    out dx, al

    mov bx, 0
_wait1:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait1; 16

    mov al, 'l'
    out dx, al

    mov bx, 0
_wait2:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait2; 16

    mov al, 'a'
    out dx, al

    mov bx, 0
_wait3:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait3; 16

    mov al, 13
    out dx, al

    mov bx, 0
_wait4:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait4; 16

    mov al, 10
    out dx, al

    mov dx, 0x378
    mov al, 0b11011011
    out dx, al

    mov bx, 0
_wait5:
    inc bx; 3
    cmp bx, 0xFFFF; 4
    jb _wait5; 16


    jmp continue

%include "../../bios/config.serial.inc"
%include "../../bios/serial.asm"
%include "../../bios/serial_util.asm"


reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp 0xF000:start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0