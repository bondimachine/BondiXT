ORG 0x7C00            ; Boot sector starts at 0x7C00

CPU 8086
BITS 16               ; Use 16-bit real mode instructions

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    
    mov ax, 0x03          ; Set video mode to text (80x25)
    int 0x10

continue:
    mov si, prompt
    call print_string       

    mov si, name_buf         
    mov cx, NAME_MAX
    call readline     

    mov ah, 0x0E

    mov si, cr_lf
    call print_string
    mov si, hola_prefix
    call print_string
    mov si, name_buf
    call print_string
    mov si, cr_lf
    call print_string

    jmp continue


print_string:
    mov bx, 0             ; Page 0
print_loop:
    mov ah, 0x0E          ; Teletype function
    lodsb
    cmp al, 0
    je end_print
    int 0x10
    jmp print_loop
end_print:
    ret

readline:
    ; Inputs: SI = buffer, CX = max bytes
    xor dx, dx        ; bx = count
    sub cx, 1       ; reserve space for NUL
.rl_loop:
    mov ah, 0x00
    int 0x16        ; BIOS keyboard input, AL = char

    cmp al, 0x0D
    je  .rl_finish
    cmp al, 0x0A
    je  .rl_finish

    ; Check for Backspace (ASCII 0x08)
    cmp al, 0x08
    je  .rl_backspace

    cmp dx, cx
    je .rl_finish

    ; Echo back
    mov ah, 0x0E
    mov bx, 0
    int 0x10

    mov [si], al
    inc si
    inc dx
    jmp .rl_loop

.rl_backspace: 
    cmp dx, 0
    je .rl_loop
    dec si
    dec dx

    mov al, 0x08
    mov bx, 0
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .rl_loop

.rl_finish:
    mov byte [si], 0       ; NUL terminate
    ret

; ---------------------
; Data area / padding
; ---------------------

prompt db 'Nombre: ',0

NAME_MAX equ 20
name_buf times NAME_MAX db 0

hola_prefix db 'Hola ',0
cr_lf db 13,10,0

times 510 - ($ - $$) db 0

; boot signature
dw 0xAA55
