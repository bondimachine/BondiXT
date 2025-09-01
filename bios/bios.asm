%include "config.serial.inc"
BITS 16

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

    sti                   ; enable interrupts again

    call serial_init
    
    mov si, welcome_message
    call serial_print_string

    ; Copy disk image to boot sector (0x7C00)
    mov si, diskimg
    mov di, 0x7C00
    mov cx, DISK_IMAGE_SIZE
.copy_loop:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    loop .copy_loop

    mov si, boot_message
    call serial_print_string

    xor ax, ax
    mov ds, ax            ; DS = 0

    ; jump to 0x7C00 (boot sector)
    jmp 0x0000:0x7C00


%include "serial.asm"
%include "video_serial.asm"

welcome_message    db "Welcome to BondiXT!", 13, 10, 13, 10, 0
boot_message    db "Booting from embedded disk image...", 13, 10, 13, 10, 0

diskimg:
    ; you can use consoleboot.bin for example from tests/console
    incbin "disk.bin"

DISK_IMAGE_SIZE equ $ - diskimg

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp _start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0