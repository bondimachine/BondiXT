bits 16
org 0x100

start:
    ; Save old int 1Ch vector
    mov ax, 0x351C
    int 0x21
    mov [old_int1c_seg], es
    mov [old_int1c_off], bx

    ; Set new int 1Ch handler
    mov ax, cs
    mov ds, ax
    mov dx, int1c_handler
    mov ax, 0x251C
    int 0x21

    ; Read initial ticks
    call read_ticks
    mov [start_lo], dx
    mov [start_hi], cx

    ; Print start message
    mov si, start_msg
    call print_string
    mov ax, [start_hi]
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, [start_lo]
    call print_hex16
    call print_crlf

    ; Reset counter
    mov word [tick_count], 0

wait_loop:
    cmp word [tick_count], 54
    jb wait_loop

    ; Read final ticks
    call read_ticks
    mov [end_lo], dx
    mov [end_hi], cx

    ; Print end message
    mov si, end_msg
    call print_string
    mov ax, [end_hi]
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, [end_lo]
    call print_hex16
    call print_crlf

    ; Restore old int 1Ch vector
    mov dx, [old_int1c_off]
    mov ax, [old_int1c_seg]
    mov ds, ax
    mov ax, 0x251C
    int 0x21

    ; Exit
    mov ah, 0x4C
    int 0x21

int1c_handler:
    push ax
    push bx
    push cx
    push dx
    push si
    push ds

    mov ax, cs
    mov ds, ax

    ; Increment tick count
    inc word [tick_count]

    ; Read current ticks
    call read_ticks

    ; Print current ticks
    mov si, current_msg
    call print_string
    mov ax, cx  ; high word
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, dx  ; low word
    call print_hex16
    call print_crlf

    pop ds
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

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

start_msg    db "Start ticks=", 0
end_msg      db "End   ticks=", 0
current_msg  db "Current ticks=", 0

start_lo     dw 0
start_hi     dw 0
end_lo       dw 0
end_hi       dw 0
tick_count   dw 0
old_int1c_off dw 0
old_int1c_seg dw 0