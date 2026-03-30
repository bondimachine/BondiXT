CPU 8086
org 0x100

start:

    mov ax, 0x0003
    int 0x10

    mov dx, 0x3D8
    mov al, 0b01001 ; high res text mode, output enabled
    out dx, al

    mov dx, 0x3DF
    mov al, 0 ;; cls
    out dx, al

    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 80*25
    mov ax, 0x0741  ; 'A' with attribute
    rep stosw


    mov ah, 0x4C
    int 0x21