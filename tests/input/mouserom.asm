ORG 0x7C00            ; Boot sector starts at 0x7C00

BITS 16

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    mov ds, ax
    mov es, ax

    mov ax, 0x03          ; Set video mode to text (80x25)
    int 0x10

    mov si, hello_msg
    call print_string

    ; Initialize state
    mov word [cur_x], 0
    mov word [cur_y], 0
    mov word [cur_btn], 0
    mov byte [changed], 0
    mov byte [mouse_byte_count], 0

    ; --- Install our own IRQ12 handler (INT 0x74) ---
    cli
    xor ax, ax
    mov es, ax
    mov word [es:0x74*4], irq12_handler
    mov word [es:0x74*4+2], cs

    ; --- Initialize PS/2 mouse directly ---

    ; Enable auxiliary PS/2 port
    ; call wait_ps2_input
    mov al, 0xA8
    out 0x64, al

    ; Read controller config byte
    call wait_ps2_input
    mov al, 0x20          ; Command: read config byte
    out 0x64, al
    call wait_ps2_output
    in al, 0x60
    or al, 0x02           ; Set bit 1: enable auxiliary (IRQ12) interrupt
    and al, ~0x20         ; Clear bit 5: don't disable auxiliary clock
    push ax

    ; Write controller config byte back
    call wait_ps2_input
    mov al, 0x60          ; Command: write config byte
    out 0x64, al
    call wait_ps2_input
    pop ax
    out 0x60, al

    ; Enable data reporting / streaming mode (command 0xF4)
    mov al, 0xF4
    call send_mouse_cmd

    ; Unmask IRQ12 on slave PIC (bit 4) and IRQ2 on master (bit 2, cascade)
    in al, 0xA1
    and al, 0xEF          ; Clear bit 4 -> unmask IRQ12
    out 0xA1, al
    in al, 0x21
    and al, 0xFB          ; Clear bit 2 -> unmask IRQ2 (cascade)
    out 0x21, al

    sti

    mov si, ready_msg
    call print_string

poll_loop:
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
    hlt
    jmp poll_loop

; -----------------------------------------------
; send_mouse_cmd: Send byte in AL to mouse device
;   Waits for ACK (0xFA) response
; -----------------------------------------------
send_mouse_cmd:
    push ax
    call wait_ps2_input
    push ax
    mov al, 0xD4          ; Tell controller: next byte to auxiliary
    out 0x64, al
    pop ax
    call wait_ps2_input
    pop ax
    out 0x60, al
    call wait_ps2_output
    in al, 0x60           ; Read ACK
    ret

; -----------------------------------------------
; PS/2 controller helpers
; -----------------------------------------------
wait_ps2_input:
    in al, 0x64
    test al, 0x02
    jnz wait_ps2_input
    ret

wait_ps2_output:
    in al, 0x64
    test al, 0x01
    jz wait_ps2_output
    ret

; -----------------------------------------------
; IRQ12 handler: reads PS/2 mouse bytes directly
;   Collects 3-byte packets, updates position
; -----------------------------------------------
irq12_handler:
    push ax
    push bx
    push ds

    xor ax, ax
    mov ds, ax

    ; Read byte from PS/2 data port
    in al, 0x60

    ; Which byte in the 3-byte packet?
    mov bl, [mouse_byte_count]

    cmp bl, 0
    je .byte0
    cmp bl, 1
    je .byte1
    jmp .byte2

.byte0:
    ; First byte = status (buttons, sign bits, overflow)
    ; Bit 3 should always be set in a valid first byte
    test al, 0x08
    jz .done_irq          ; Not a valid first byte, resync

    mov [mouse_packet], al
    mov byte [mouse_byte_count], 1
    jmp .done_irq

.byte1:
    ; Second byte = X delta
    mov [mouse_packet+1], al
    mov byte [mouse_byte_count], 2
    jmp .done_irq

.byte2:
    ; Third byte = Y delta — packet complete
    mov [mouse_packet+2], al
    mov byte [mouse_byte_count], 0

    ; --- Process complete packet ---

    ; Buttons (bits 0-2 of status byte)
    mov al, [mouse_packet]
    and al, 0x07
    xor ah, ah
    mov [cur_btn], ax

    ; X delta: sign-extend using bit 4 of status byte
    mov al, [mouse_packet+1]
    test byte [mouse_packet], 0x10   ; X sign bit
    jz .x_pos
    mov ah, 0xFF                     ; negative: sign-extend
    jmp .x_done
.x_pos:
    xor ah, ah
.x_done:
    add [cur_x], ax

    ; Y delta: sign-extend using bit 5 of status byte, negate for screen
    mov al, [mouse_packet+2]
    test byte [mouse_packet], 0x20   ; Y sign bit
    jz .y_pos
    mov ah, 0xFF
    jmp .y_done
.y_pos:
    xor ah, ah
.y_done:
    neg ax
    add [cur_y], ax

    mov byte [changed], 1

.done_irq:
    ; Send EOI to slave PIC then master PIC
    mov al, 0x20
    out 0xA0, al
    out 0x20, al

    pop ds
    pop bx
    pop ax
    iret

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
    shr al, cl
    call .nibble
    pop ax
    push ax
    and al, 0x0F
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
    push ax
    mov al, '-'
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    pop ax
    neg ax

.positive:
    xor cx, cx

.div_loop:
    xor dx, dx
    mov bx, 10
    div bx
    push dx
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
hello_msg db 'H', 13, 10, 0
ready_msg db 'R', 13, 10, 0

lbl_x   db 'X:', 0
lbl_y   db ' Y:', 0
lbl_btn db 'B:', 0
crlf    db 13, 10, 0

cur_x    dw 0
cur_y    dw 0
cur_btn  dw 0
changed  db 0

mouse_byte_count db 0
mouse_packet     db 0, 0, 0

times 510 - ($ - $$) db 0
dw 0xAA55
