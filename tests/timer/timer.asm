bits 16
org 0x100

start:
    call read_ticks
    mov [start_lo], dx
    mov [start_hi], cx

    mov si, start_msg
    call print_string
    mov ax, [start_hi]
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, [start_lo]
    call print_hex16
    call print_crlf

    mov bx, [start_lo]
    mov bp, [start_hi]

wait_loop:
    call read_ticks
    mov [end_lo], dx
    mov [end_hi], cx

    mov ax, dx
    sub ax, bx
    mov dx, cx
    sbb dx, bp
    cmp dx, 0
    jne ready_to_print
    cmp ax, 54
    jb wait_loop

ready_to_print:

    mov si, end_msg
    call print_string
    mov ax, [end_hi]
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, [end_lo]
    call print_hex16
    call print_crlf

    mov ah, 0x4C
    int 0x21

read_ticks:
    mov ah, 0x00
    int 0x1A
    ret

print_string:
    mov ah, 0x0E
.next_char:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .next_char
.done:
    ret

print_char:
    mov ah, 0x0E
    int 0x10
    ret

print_crlf:
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    ret

print_hex16:
    push ax
    push bx
    push cx
    push dx

    mov bx, 4
    mov cx, ax

.hex_loop:
    mov dx, cx
    and dx, 0xF000
    shr dx, 12
    cmp dl, 10
    jl .hex_digit
    add dl, 'A' - 10
    jmp .hex_out
.hex_digit:
    add dl, '0'
.hex_out:
    mov ah, 0x0E
    mov al, dl
    int 0x10
    shl cx, 4
    dec bx
    jnz .hex_loop

    pop dx
    pop cx
    pop bx
    pop ax
    ret

start_msg db "Start ticks=", 0
end_msg   db "End   ticks=", 0

start_lo dw 0
start_hi dw 0
end_lo   dw 0
end_hi   dw 0
