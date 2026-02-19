ORG 0x7C00            ; Boot sector starts at 0x7C00

BITS 16

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    mov ds, ax
    sti

    mov ax, 0x03          ; Set video mode to text (80x25)
    int 0x10

    mov si, hello_msg
    call print_string

    ; Initialize state
    mov word [cur_x], 0
    mov word [cur_y], 0
    mov word [cur_btn], 0
    mov byte [changed], 0

    ; --- Set up PS/2 mouse via INT 15h/C2h ---
    mov bh, 3
    mov ax, 0xC205
    int 0x15

    ; Set driver callback address (INT 15h/C2h, AL=07h)
    ; ES:BX = far pointer to our callback
    push cs
    pop es                ; ES = 0 (same as DS)
    mov bx, mouse_callback
    mov ax, 0xC207
    int 0x15

    ; Enable mouse
    mov ax, 0xC200
    mov bh, 0x01
    int 0x15

    mov si, ready_msg
    call print_string

poll_loop:
    ; Check if the callback flagged a change
    cli
    cmp byte [changed], 0
    je .no_change

    ; Reset flag
    mov byte [changed], 0
    sti

    ; Print "X:"
    mov si, lbl_x
    call print_string
    mov ax, [cur_x]
    call print_signed

    ; Print " Y:"
    mov si, lbl_y
    call print_string
    mov ax, [cur_y]
    call print_signed

    ; Print " B:"
    mov si, lbl_btn
    call print_string
    mov ax, [cur_btn]
    call print_hex8

    ; Print newline
    mov si, crlf
    call print_string

    jmp poll_loop

.no_change:
    sti
    hlt                   ; Wait for next interrupt
    jmp poll_loop


; -----------------------------------------------
; mouse_callback: called from BIOS IRQ12 handler
;   BIOS pushes: status, X delta, Y delta, 0
;   then does CALL FAR, so stack after push bp is:
;     [BP+12] = status byte (buttons + sign/overflow)
;     [BP+10] = X delta
;     [BP+8]  = Y delta
;     [BP+6]  = 0
;     [BP+4]  = return CS
;     [BP+2]  = return IP
;     [BP+0]  = saved BP
; -----------------------------------------------
mouse_callback:
    push bp
    mov bp, sp
    push ax
    push bx
    push ds

    xor ax, ax
    mov ds, ax            ; DS = 0

    ; --- Status byte from the PS/2 packet ---
    mov bx, [bp+12]      ; BL = status byte

    ; --- Buttons: bits 0-2 of status byte ---
    mov al, bl
    and al, 0x07
    mov [cur_btn], al

    ; --- X delta ---
    mov al, [bp+10]      ; X movement (signed byte)
    cbw                   ; sign-extend AL -> AX
    add [cur_x], ax

    ; --- Y delta (PS/2 Y is inverted, negate for screen coords) ---
    mov al, [bp+8]       ; Y movement (signed byte)
    cbw
    neg ax
    add [cur_y], ax

    ; Flag that something changed
    mov byte [changed], 1

    pop ds
    pop bx
    pop ax
    pop bp
    retf

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
; print_hex8: print AL as 2-digit hex
; -----------------------------------------------
print_hex8:
    push cx
    push ax
    mov cl, 4
    shr al, cl            ; high nibble
    call .nibble
    pop ax
    push ax
    and al, 0x0F          ; low nibble
    call .nibble
    pop ax
    pop cx
    ret
.nibble:
    cmp al, 10
    jb .digit
    add al, 'A' - 10 - '0'
.digit:
    add al, '0'
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    ret

; -----------------------------------------------
; print_signed: print AX as signed decimal
; -----------------------------------------------
print_signed:
    push ax
    push bx
    push cx
    push dx

    test ax, ax
    jns .positive
    ; Print '-'
    push ax
    mov al, '-'
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    pop ax
    neg ax

.positive:
    ; AX = unsigned value to print
    xor cx, cx           ; digit count

.div_loop:
    xor dx, dx
    mov bx, 10
    div bx               ; AX = quotient, DX = remainder
    push dx              ; push digit
    inc cx
    test ax, ax
    jnz .div_loop

.print_digits:
    pop ax
    add al, '0'
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    loop .print_digits

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------------------------
; Data
; -----------------------------------------------
hello_msg db 'BondiXT Mouse Test', 13, 10, 0
ready_msg db 'Mouse enabled. Move mouse...', 13, 10, 0

lbl_x   db 'X:', 0
lbl_y   db ' Y:', 0
lbl_btn db ' B:', 0
crlf    db 13, 10, 0

cur_x    dw 0
cur_y    dw 0
cur_btn  dw 0

changed  db 0

times 510 - ($ - $$) db 0

; boot signature
dw 0xAA55
