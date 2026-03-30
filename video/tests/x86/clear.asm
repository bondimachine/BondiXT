CPU 8086
org 0x100

start:

    mov dx, 0x3DF
    mov al, 0 ;; cls
    out dx, al

    mov dx, 0x3d4
    mov al, 0xe
    out dx, al

    inc dx
    mov al, 0
    out dx, al

    dec dx
    mov al, 0xf
    out dx, al

    inc dx
    mov al, 0
    out dx, al

    mov ah, 0x4C
    int 0x21