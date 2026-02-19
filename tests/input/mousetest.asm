ORG 0x100              ; DOS .COM file

BITS 16

start:
    ; Reset / initialize mouse driver
    xor ax, ax
    int 0x33
    cmp ax, 0xFFFF
    je .mouse_ok

    mov si, no_mouse_msg
    call print_string
    int 0x20              ; exit to DOS

.mouse_ok:
    ; Show mouse cursor
    mov ax, 0x01
    int 0x33

    ; Initialize "previous" values to impossible values so first read always prints
    mov word [prev_x], 0xFFFF
    mov word [prev_y], 0xFFFF
    mov word [prev_btn], 0xFFFF

poll_loop:
    ; Check keyboard — non-blocking
    mov ah, 0x01
    int 0x16
    jz .no_key
    ; Consume the key
    mov ah, 0x00
    int 0x16
    cmp al, 0x1B          ; ESC?
    je exit
.no_key:

    ; Get mouse position and button status
    mov ax, 0x03
    int 0x33
    ; BX = button status, CX = X, DX = Y

    ; Compare with previous values
    cmp cx, [prev_x]
    jne .changed
    cmp dx, [prev_y]
    jne .changed
    cmp bx, [prev_btn]
    jne .changed
    jmp poll_loop

.changed:
    ; Save new values
    mov [prev_x], cx
    mov [prev_y], dx
    mov [prev_btn], bx

    ; Print "X:"
    push bx
    push cx
    push dx

    mov si, lbl_x
    call print_string
    pop dx
    push dx
    mov ax, [prev_x]
    call print_hex16

    ; Print " Y:"
    mov si, lbl_y
    call print_string
    mov ax, [prev_y]
    call print_hex16

    ; Print " B:"
    mov si, lbl_btn
    call print_string
    mov ax, [prev_btn]
    call print_hex16

    ; Print newline
    mov si, crlf
    call print_string

    pop dx
    pop cx
    pop bx

    jmp poll_loop

exit:
    ; Hide mouse cursor
    mov ax, 0x02
    int 0x33

    int 0x20              ; exit to DOS

; -----------------------------------------------
; print_string: print NUL-terminated string at SI
; -----------------------------------------------
print_string:
    mov ah, 0x0E
    xor bx, bx
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    ret

; -----------------------------------------------
; print_hex16: print AX as 4-digit hex
; -----------------------------------------------
print_hex16:
    push cx
    mov cx, 4             ; 4 nibbles
    rol ax, 4             ; start with high nibble
.loop:
    push ax
    and al, 0x0F
    cmp al, 10
    jb .digit
    add al, 'A' - 10 - '0'
.digit:
    add al, '0'
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    pop ax
    rol ax, 4
    loop .loop
    pop cx
    ret

; -----------------------------------------------
; Data
; -----------------------------------------------
no_mouse_msg db 'Mouse driver not found!', 13, 10, 0

lbl_x   db 'X:', 0
lbl_y   db ' Y:', 0
lbl_btn db ' B:', 0
crlf    db 13, 10, 0

prev_x   dw 0
prev_y   dw 0
prev_btn dw 0
