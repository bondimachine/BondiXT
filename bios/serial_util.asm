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
    mov cl, 4
    shr al, cl
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