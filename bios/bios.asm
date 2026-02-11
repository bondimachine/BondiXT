%include "config.serial.inc"
BITS 16
CPU 8086

; DISK_IMAGE_SEGMENT equ 0xE000 ; 0xE0000 / 16

DISK_IMAGE_SEGMENT equ 0xFE00 ; 8 kb rom

POST_ADDRESS equ 0x378 ; parallel port for POST code output until we move it to 0x80

times 0xF000 - ($ - $$) db 0 ; BIOS code starts at 0xF000 

_start:
    cli                   ; disable interrupts during setup
    mov ax, cs
    mov ds, ax            ; DS = CS
    xor ax, ax
    mov ss, ax            ; SS
    mov sp, 0xFFFE       ; set up stack at the end of the segment 

    mov dx, POST_ADDRESS
    mov al, 0b11000001
    out dx, al

    xor ax, ax
    mov es, ax            ; ES = 0

    mov si, 0x40
    mov word [es:si], int10_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x44
    mov word [es:si], int11_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x48
    mov word [es:si], int12_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x4c
    mov word [es:si], int13_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x50
    mov word [es:si], int14_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x54
    mov word [es:si], int15_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x58
    mov word [es:si], int16_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x5c
    mov word [es:si], int17_handler
    add si, 2
    mov word [es:si], cs

    mov si, 0x68
    mov word [es:si], int1Ah_handler
    add si, 2
    mov word [es:si], cs

    sti                   ; enable interrupts again


    mov dx, POST_ADDRESS
    mov al, 0b11000010
    out dx, al

    call serial_init
    
    mov si, welcome_message
    call serial_print_string

    ; intialize video
    call init_video

    mov ax, 0
    mov es, ax

    mov dx, POST_ADDRESS
    mov al, 0b11000011
    out dx, al

    ; copy the boot sector to 0x7C00
    mov ah, 02h
    mov al, 1 ; copy 1 sector
    mov cx, 1 ; from cylinder 0 sector 1 (sector 1 based)
    mov dx, 0 ; head 0 drive 0
    mov bx, 0x7C00
    int 13h

    push cs
    pop ds

    mov dx, POST_ADDRESS
    mov al, 0b11000100
    out dx, al

    mov si, boot_message
    call serial_print_string

    xor ax, ax
    mov ds, ax            ; DS = 0

    mov dx, POST_ADDRESS
    mov al, 0b11011011
    out dx, al

    ; jump to 0x7C00 (boot sector)
    jmp 0x0000:0x7C00


%include "serial.asm"
%include "serial_util.asm"
%include "video_serial.asm"
; %include "video_custom.asm"
%include "keyboard_serial.asm"
%include "disk_embedded.asm"


int11_handler:
    ; 1 floppy 
    ; 80x25 cga
    ; 1 rs232 port
    mov ax, 0x221
    iret

int12_handler:
    mov ax, 640 ; conventional memory is 640kb
    iret

int15_handler:
    stc
    iret

int17_handler:
    mov ah, 0
    iret

int1Ah_handler:
    iret

welcome_message    db "Welcome to BondiXT!", 13, 10, 13, 10, 0
boot_message    db "Booting from embedded disk image...", 13, 10, 13, 10, 0

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp 0xF000:_start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0