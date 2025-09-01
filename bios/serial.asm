serial_init:

    ; Initialize serial SERIAL_PORT
    mov dx, SERIAL_PORT_LCR        ; Line Control Register
    mov al, 0x80            ; Enable DLAB (set baud rate divisor)
    out dx, al

    mov dx, SERIAL_PORT_DIV_LOW    ; Divisor Latch Low Byte
    mov al, SERIAL_PORT_BAUD_DIVISOR
    out dx, al

    mov dx, SERIAL_PORT_DIV_HIGH   ; Divisor Latch High Byte
    mov al, 0
    out dx, al

    mov dx, SERIAL_PORT_LCR        ; Line Control Register
    mov al, 0x03            ; 8 bits, no parity, one stop bit
    out dx, al

    mov dx, SERIAL_PORT_MCR        ; Modem Control Register
    mov al, 0x03            ; RTS and DTR set
    out dx, al
    
    ret


; ---------------------
; serial_putc: AL = char -> write to COM1, wait TX empty
; ---------------------
serial_putc:
    ; wait for Transmitter Holding Register Empty (LSR bit 5 = 0x20) at SERIAL_PORT 0x3FD
.wait_tx:
    push ax
    mov dx, SERIAL_PORT_LSR
    in  al, dx
    test al, 0x20
    jz  .wait_tx
    ; send char
    mov dx, SERIAL_PORT
    pop ax
    out dx, al
    ret

; ---------------------
; serial_getc: returns character in AL (polling)
; ---------------------
serial_getc:
    ; wait for Data Ready (LSR bit 0 = 0x01)
.wait_rx:
    mov dx, SERIAL_PORT_LSR
    in  al, dx
    test al, 0x01
    jz  .wait_rx
    ; read received byte from RBR (0x3F8)
    mov dx, SERIAL_PORT
    in  al, dx
    ret

; ---------------------
; print string pointed by SI (zero-terminated).
; ---------------------
serial_print_string:
    lodsb
    cmp al, 0
    je  .done
    call serial_putc
    jmp serial_print_string
.done:
    ret

serial_readline:
    ; Inputs: SI = buffer, CX = max bytes
    xor bx, bx        ; bx = count
    sub cx, 1       ; reserve space for NUL
.rl_loop:
    call serial_getc       ; AL = char

    cmp al, 0x0D
    je  .rl_finish
    cmp al, 0x0A
    je  .rl_finish

    ; Check for Backspace (ASCII 0x08)
    cmp al, 0x08
    je  .rl_backspace

    cmp bx, cx
    je .rl_finish

    call serial_putc       ; echo back

    mov [si], al
    inc si
    inc bx
    jmp .rl_loop

.rl_backspace: ; TODO: handle properly
    cmp bx, 0
    je .rl_loop
    dec si
    dec bx
    mov al, 0x08
    call serial_putc
    mov al, ' '
    call serial_putc
    mov al, 0x08
    call serial_putc
    jmp .rl_loop

.rl_finish:
    mov byte [si], 0       ; NUL terminate
    ret

serial_print_hex:
    ; Input: AL = byte to print in hex
    push ax
    push bx
    push cx
    mov bl, al
    shr al, 4
    call .print_nibble

    mov al, bl
    call .print_nibble
    pop cx
    pop bx
    pop ax
    ret 

.print_nibble:
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .print
.digit:
    add al, '0'
.print:
    call serial_putc
    ret
