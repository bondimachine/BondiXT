ORG 0x100

start:
    ; Install INT 9 handler
    cli                         ; Disable interrupts
    mov ax, 0x0000
    mov es, ax
    mov word [es:0x24], int9_handler  ; Store INT 9 offset
    mov word [es:0x26], cs      ; Store INT 9 segment
    sti                         ; Enable interrupts

    ; Print startup message
    mov si, startup_msg
print_msg:
    lodsb
    or al, al
    jz main_loop
    mov ah, 0x0E                ; Teletype output
    int 0x10
    jmp print_msg

main_loop:
    ; Check if there's a character in the buffer
    mov al, [buffer_head]
    mov bl, [buffer_tail]
    cmp al, bl
    je main_loop                ; No character available, wait

    ; Get character from buffer
    mov al, [buffer + bx]
    inc bl
    and bl, (BUFFER_SIZE - 1)   ; Wrap around buffer
    mov [buffer_tail], bl

    ; Print character via BIOS
    mov ah, 0x0E                ; Teletype output
    int 0x10

    jmp main_loop               ; Loop forever

; INT 9 Handler (keyboard interrupt)
int9_handler:
    push ax
    push bx
    push ds
    
    mov ax, cs
    mov ds, ax
    
    ; Read scancode from port 0x60
    in al, 0x60
    
    ; Filter out break codes (key releases)
    test al, 0x80
    jnz int9_exit
    
    ; Map scancode to ASCII
    mov bl, al
    xor bh, bh
    cmp bx, SCANCODE_TABLE_LEN
    jae int9_exit
    
    mov al, [scancode_table + bx]
    or al, al
    jz int9_exit                ; Ignore non-printable keys
    
    ; Add character to buffer
    mov bx, [buffer_head]
    mov [buffer + bx], al
    inc bl
    and bl, (BUFFER_SIZE - 1)   ; Wrap around buffer
    mov [buffer_head], bl

int9_exit:
    ; Send EOI (End Of Interrupt) to interrupt controller
    mov al, 0x20
    out 0x20, al
    
    pop ds
    pop bx
    pop ax
    iret

; Keyboard buffer (ring buffer, 16 bytes)
buffer_head db 0                ; Write pointer
buffer_tail db 0                ; Read pointer
BUFFER_SIZE equ 16
buffer: db BUFFER_SIZE dup(0)

startup_msg db "INT 9 Keyboard Interrupt Handler. Press keys...", 13, 10, 0

; Scancode to ASCII table (Set 1 subset)
scancode_table:
    db 0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', 8, 9
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0, 'a','s'
    db 'd','f','g','h','j','k','l',';', 39, '`', 0, '\','z','x','c','v'
    db 'b','n','m',',','.','/', 0, '*', 0, ' '
SCANCODE_TABLE_LEN equ $ - scancode_table
