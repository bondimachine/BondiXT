ORG 0x100

start:
    ; Print startup message
    mov si, startup_msg
print_msg:
    lodsb
    or al, al
    jz poll_loop
    mov ah, 0x0E ; Teletype output
    int 0x10
    jmp print_msg

poll_loop:
    ; Poll Status Register (Port 0x64)
    in al, 0x64
    test al, 1          ; Bit 0: Output Buffer Full (key available)
    jz poll_loop

    ; Read Data Register (Port 0x60)
    in al, 0x60

    ; Filter out break codes (key releases)
    test al, 0x80
    jnz poll_loop

    ; Map scancode to ASCII
    mov bl, al
    xor bh, bh
    cmp bx, SCANCODE_TABLE_LEN
    jae unknown_key

    mov al, [cs:scancode_table + bx]
    or al, al
    jz poll_loop        ; Ignore non-printable keys

    ; Print character via BIOS
    mov ah, 0x0E        ; Teletype output
    int 0x10

    jmp poll_loop       ; Loop forever

unknown_key:
    jmp poll_loop

startup_msg db "Direct Keyboard Polling (Port 0x60/0x64). Press keys...", 13, 10, 0

; Scancode to ASCII table (Set 1 subset)
scancode_table:
    db 0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', 8, 9
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0, 'a','s'
    db 'd','f','g','h','j','k','l',';', 39, '`', 0, '\','z','x','c','v'
    db 'b','n','m',',','.','/', 0, '*', 0, ' '
SCANCODE_TABLE_LEN equ $ - scancode_table
