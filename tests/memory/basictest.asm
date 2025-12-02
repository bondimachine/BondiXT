BITS 16

P0 EQU 0b01010101
P1 EQU 0b10101010

; %define QEMU

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

start:

    mov ax, 0
    mov ds, ax
    mov si, 0

    mov dx, 0x378

continue:
    mov al, P0
    mov [ds:si], al
    mov al, [ds:si]
    out dx, al

    mov cx, 0xFFFF
.loop:    
    dec cx
    jnz .loop

    mov al, P1
    mov [ds:si], al
    mov al, [ds:si]
    out dx, al

    mov cx, 0xFFFF
.loop2:    
    dec cx
    jnz .loop2

    inc si
    jnz continue
    mov ax, ds
    add ax, 0x1000
    mov ds, ax

    jmp continue

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0