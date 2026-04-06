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

    ; Set VGA mode 13h (320x200, 256 colors)
    ; Standard VGA BIOS interrupt
    mov ax, 0x0013
    int 0x10

    ; Start with color 1
    mov bl, 1

.loop_colors:
    ; Wait for vsync before filling screen
    call wait_vsync

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
    xor di, di

    ; Fill the entire screen (320 * 200 = 64,000 pixels)
    ; AL = color index (from BL)
    ; CX = number of pixels
    mov al, bl
    mov cx, 64000
    cld

    rep stosb

    ; Increment color index (will wrap around from 255 to 0)
    inc bl

    jmp .loop_colors

wait_vsync:
    ; Wait for vertical retrace (vsync)
    ; Port 0x3DA is the Input Status Register
    ; Bit 3 (0x08) indicates vertical retrace in progress
    mov dx, 0x3DA
    
.wait_in_vsync:
    in al, dx
    and al, 0x08
    jz .wait_in_vsync
    
    ret

    ; times 510-($-$$) db 0
    ; dw 0xAA55