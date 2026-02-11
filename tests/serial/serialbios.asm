BITS 16

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

start:
    
    mov ax, cs
    mov ds, ax
    mov es, ax


    mov dx, 0x378
    mov al, 0b11000011
    out dx, al


    call serial_init

    mov si, prompt
    call serial_print_string       


    mov dx, 0x378
    mov al, 0b11011011
    out dx, al

    ; we are running in ROM, so we need the buffer to be in RAM
    mov ax, 0x1000
    mov ds, ax
    mov si, 0         
    mov cx, NAME_MAX
    call serial_readline     
    mov ax, cs
    mov ds, ax

    mov si, cr_lf
    call serial_print_string
    mov si, hola_prefix
    call serial_print_string

    mov ax, 0x1000
    mov ds, ax
    mov si, 0
    call serial_print_string
    mov ax, cs
    mov ds, ax

    mov si, cr_lf
    call serial_print_string

    jmp start

%include "../../bios/config.serial.inc"
%include "../../bios/serial.asm"
%include "../../bios/serial_util.asm"

; ---------------------
; Data area / padding
; ---------------------

prompt db 'Nombre: ',0

NAME_MAX equ 20

hola_prefix db 'Hola ',0
cr_lf db 13,10,0

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp 0xF000:start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0