org 0x7C00

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    
    call serial_init

    mov si, prompt
    call serial_print_string       

    mov si, name_buf         
    mov cx, NAME_MAX
    call serial_readline     

    mov si, cr_lf
    call serial_print_string
    mov si, hola_prefix
    call serial_print_string
    mov si, name_buf
    call serial_print_string
    mov si, cr_lf
    call serial_print_string

    jmp start

; ---------------------
; Functions using INT 14h
; ---------------------

serial_init:
    mov ah, 0x00      ; Function 00h: Initialize port
    mov al, 0xE3      ; 9600 baud, 8-N-1
    mov dx, 0         ; COM1
    int 0x14
    ret

serial_putc:
    mov ah, 0x01      ; Function 01h: Send character
    mov dx, 0         ; COM1
    int 0x14
    ret

serial_getc:
    mov ah, 0x02      ; Function 02h: Receive character
    mov dx, 0         ; COM1
    int 0x14          ; Character in AL
    ret

%include "../../bios/serial_util.asm"

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
