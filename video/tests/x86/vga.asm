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

    ; Read current ticks from BIOS
    mov ah, 0x00
    int 0x1A          ; CX = high word, DX = low word

    ; Print CX (high-order word of system clock count)
    mov ax, cx
    call print_serial_hex16

    ; Print ':'
    mov al, ':'
    call send_serial_char

    ; Print DX (low-order word of system clock count)
    mov ax, dx
    call print_serial_hex16

    ; Print ' - ' separator
    mov al, ' '
    call send_serial_char
    mov al, '-'
    call send_serial_char
    mov al, ' '
    call send_serial_char

    ; Print BL (current color)
    mov al, bl
    call print_serial_hex8

    ; Print carriage return and line feed
    mov al, 0x0D
    call send_serial_char
    mov al, 0x0A
    call send_serial_char

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

send_serial_char:
    ; Sends character in AL to COM1 (port dx=0)
    push dx
    push ax
    mov ah, 0x01
    mov dx, 0
    int 0x14
    pop ax
    pop dx
    ret

print_serial_hex8:
    ; Prints AL as 2 hex characters
    push cx
    push ax
    
    ; High nibble
    mov cl, 4
    shr al, cl
    call .print_nibble
    
    ; Low nibble
    pop ax
    push ax
    and al, 0x0F
    call .print_nibble

    pop ax
    pop cx
    ret

.print_nibble:
    cmp al, 10
    jl .is_digit
    add al, 'A' - 10
    jmp .send
.is_digit:
    add al, '0'
.send:
    call send_serial_char
    ret

print_serial_hex16:
    ; Prints AX as 4 hex characters
    push ax
    mov al, ah
    call print_serial_hex8
    pop ax
    call print_serial_hex8
    ret

    ; times 510-($-$$) db 0
    ; dw 0xAA55