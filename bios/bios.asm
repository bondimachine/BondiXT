%include "config.serial.inc"
BITS 16

DISK_IMAGE_SEGMENT equ 0xE000 ; 0xE0000 / 16

times 0xF000 - ($ - $$) db 0 ; BIOS code starts at 0xF000 

_start:
    cli                   ; disable interrupts during setup
    push cs
    pop ds

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

    mov si, 0x58
    mov word [es:si], int16_handler
    add si, 2
    mov word [es:si], cs

    sti                   ; enable interrupts again

    call serial_init
    
    mov si, welcome_message
    call serial_print_string

    ; Copy disk image to boot sector (0x7C00)
    mov ax, DISK_IMAGE_SEGMENT
    mov ds, ax            ; DS = DISK_IMAGE
    mov si, 0
    mov di, 0x7C00
    mov cx, 512
.copy_loop:
    mov al, [ds:si]
    mov [es:di], al
    inc si
    inc di
    loop .copy_loop

    push cs
    pop ds

    mov si, boot_message
    call serial_print_string

    xor ax, ax
    mov ds, ax            ; DS = 0

    ; jump to 0x7C00 (boot sector)
    jmp 0x0000:0x7C00


%include "serial.asm"
%include "serial_util.asm"
%include "video_serial.asm"
%include "keyboard_serial.asm"
%include "disk_embedded.asm"


int11_handler:
    ; 1 floppy 
    ; 80x25 mono
    ; 1 rs232 port
    mov ax, 0x231
    iret

int12_handler:
    mov ax, 1024 ; 1MB
    iret


welcome_message    db "Welcome to BondiXT!", 13, 10, 13, 10, 0
boot_message    db "Booting from embedded disk image...", 13, 10, 13, 10, 0

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp _start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0