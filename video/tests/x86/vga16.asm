CPU 8086
; org 0x7C00
org 0x100

start:
    ; Setup segment registers for boot sector
    ; xor ax, ax
    ; mov ds, ax
    ; mov es, ax
    ; mov ss, ax
    ; mov sp, 0x7C00

    ; Set VGA mode 12h (640x480, 16 colors)
    ; Standard VGA BIOS interrupt
    mov ax, 0x0012
    int 0x10

    ; Start with color 0
    mov bl, 1

.loop_colors:

    mov ah, 0x01      ; Function 01h: Send character
    mov dx, 0         ; COM1
    mov al, bl
    mov cl, 4
    shr al, cl
    cmp al, 10
    jl .is_digit
    add al, 'A' - 10
    jmp .send_char
.is_digit:
    add al, '0'
.send_char:
    int 0x14

    mov ah, 0x01      ; Function 01h: Send character
    mov al, bl
    and al, 0x0F
    cmp al, 10
    jl .is_digit2
    add al, 'A' - 10
    jmp .send_char2
.is_digit2:
    add al, '0'
.send_char2:
    int 0x14

    mov ah, 0x01
    mov al, 0x0D
    int 0x14

    mov ah, 0x01
    mov al, 0x0A
    int 0x14

    ; Point ES to video memory
    mov ax, 0xA000
    mov es, ax

    ; Write one full plane at a time (plane 0..3)
    ; BH = plane bit mask (1, 2, 4, 8); BL = color (preserved)
    mov bh, 1

.plane_loop:
    ; Set Map Mask (0x3C4 index 2) to select only the current plane
    mov dx, 0x3C4
    mov al, 2
    out dx, al
    inc dx
    mov al, bh
    out dx, al

    ; If the color bit for this plane is set, fill 0xFF, else 0x00
    test bl, bh
    mov al, 0x00
    jz .do_fill
    mov al, 0xFF

.do_fill:
    xor di, di
    mov cx, 0xFFFF
    cld
    rep stosb

    ; Advance to next plane
    shl bh, 1
    cmp bh, 0x10
    jne .plane_loop

    ; Increment color index (0-15)
    inc bl
    cmp bl, 16
    jne .loop_colors
    mov bl, 0
    jmp .loop_colors

    ; times 510-($-$$) db 0
    ; dw 0xAA55