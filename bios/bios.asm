; %define PS2_MOUSE
; %define PS2_MOUSE_IRQ_2
%define PS2_KEYBOARD
%include "config.serial.inc"
BITS 16
CPU 8086

DISK_IMAGE_SEGMENT equ 0xE000 ; 0xE0000 / 16

; DISK_IMAGE_SEGMENT equ 0xFE00 ; 8 kb rom

POST_ADDRESS equ 0x80 ; parallel port for POST code output until we move it to 0x80

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

    mov cx, 0
    mov si, 0

reset_ivt:
    mov word [es:si], int_dummy_handler
    add si, 2
    mov word [es:si], cs
    add si, 2
    inc cl
    jnz reset_ivt


    mov si, 0x20
    mov cl, 0

reset_irq:
    mov word [es:si], irq_dummy_handler
    add si, 2
    mov word [es:si], cs
    add si, 2
    inc cl
    cmp cl, 8
    jne reset_irq


    mov si, 0x20
    mov word [es:si], irq0_handler
    add si, 2
    mov word [es:si], cs


%ifdef PS2_MOUSE
%ifdef PS2_MOUSE_IRQ_2
    ; Given we don't have cascade, we use IRQ2 as the marker for PS/2 mouse instead of 12
    mov si, 0x28
%else
    mov si, 0x1D0
%endif    
    mov word [es:si], irq12_handler
    add si, 2
    mov word [es:si], cs
%endif

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
    
    ; intialize video
    call init_video

    mov si, welcome_message
    call print_string

    mov dx, POST_ADDRESS
    mov al, 0b11000011
    out dx, al

    call init_timer

    mov dx, POST_ADDRESS
    mov al, 0b11000100
    out dx, al


    call init_keyboard
%ifdef PS2_KEYBOARD    
    test al, 1
    jz .no_keyboard

    mov si, keyboard_detected_message
    call print_string
    jmp .init_keyboard_done

.no_keyboard:
    mov si, keyboard_not_detected_message
    call print_string

.init_keyboard_done:
%endif 

%ifdef PS2_MOUSE
    call init_mouse
%endif

    mov dx, POST_ADDRESS
    mov al, 0b11000101
    out dx, al

    mov ax, 0
    mov es, ax

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
    mov al, 0b11000110
    out dx, al

    mov si, boot_message
    call print_string

    call beep

    xor ax, ax
    mov ds, ax            ; DS = 0

    mov dx, POST_ADDRESS
    mov al, 0b11011011
    out dx, al

    ; jump to 0x7C00 (boot sector)
    jmp 0x0000:0x7C00

print_string:
    lodsb
    cmp al, 0
    je  .done
    mov ah, 0x0e
    int 10h
    jmp print_string
.done:
    ret


%include "serial.asm"
%include "serial_util.asm"
; %include "video_serial.asm"
%include "video_custom.asm"
%include "keyboard_serial.asm"
%include "disk_embedded.asm"
%include "timer.asm"

%ifdef PS2_MOUSE
%include "mouse.asm"
%endif


int11_handler:
    ; 1 floppy 
    ; 80x25 cga
    ; 1 rs232 port
    ; mouse
%ifdef PS2_MOUSE
    mov ax, 0x225
%else
    mov ax, 0x221
%endif
    iret

int12_handler:
    mov ax, 640 ; conventional memory is 640kb
    iret

int15_handler:
%ifdef PS2_MOUSE
    cmp	ah, 0xC2
    jne .default
    jmp int15_mouse

.default:
%endif
    stc
    iret

int17_handler:
    mov ah, 0
    iret

int_dummy_handler:
    iret    

irq_dummy_handler:
    push ax
    mov	al, 0x20 ; signal PIC
	out	0x20, al
    pop ax
    iret    

welcome_message    db "Welcome to BondiXT!", 13, 10, 13, 10, 0
boot_message    db "Booting from embedded disk image...", 13, 10, 13, 10, 0

%ifdef PS2_KEYBOARD    

keyboard_detected_message    db "Keyboard detected", 13, 10, 13, 10, 0
keyboard_not_detected_message    db "Keyboard not detected - Using serial input", 13, 10, 13, 10, 0

%endif

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp 0xF000:_start

padding: ; 64kb
    times 0xFFFE - ($ - $$) db 0

system_model:
	db	0xFE ; IBM PC/XT
	db	0xFF    