CPU 8086
org 0x100

start:

    mov ax, 0x0006
    int 0x10

    mov dx, 0x3D8
    mov al, 0b11010 
    out dx, al

    ; 640x200, 1 color
    ; Each byte: 4 pixels, 2 bits each
    ; To fill with color 1: 01010101 = 0x55
    mov ax, 0xB800
    mov es, ax

    mov al, 1
    call print

    mov al, 0x55  ; color 1 for all pixels
    call fill_screen

    mov al, 2
    call print

    mov al, 0xAA  ; color 2 for all pixels
    call fill_screen

    mov al, 3
    call print

    mov al, 0xFF  ; color 3 for all pixels
    call fill_screen

    mov ah, 0x4C
    int 0x21

fill_screen:
    xor di, di
    mov cx, 640*200 / 8  ; 16000 bytes
    rep stosb

    mov cx, 0xFFFF
.delay_inner:
    dec cx
    jnz .delay_inner
    ret

print:
    mov ah, 0x01      ; Function 01h: Send character
    mov dx, 0         ; COM1
    add al, '0'
    int 0x14

    mov ah, 0x01
    mov al, 0x0D
    int 0x14

    mov ah, 0x01
    mov al, 0x0A
    int 0x14

    ret