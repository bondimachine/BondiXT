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

%include "../../bios/config.serial.inc"
%include "../../bios/serial.asm"

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