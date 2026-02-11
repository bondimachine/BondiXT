; =============================================================================
; INT 14h - Serial Port Services
; =============================================================================
int14_handler:
    push bx
    push cx
    push dx
    push si
    
    ; We only support COM1 (DX=0)
    cmp dx, 0
    jne .unsupported_port

    cmp ah, 0
    je .init_port

    cmp ah, 1
    je .send_char

    cmp ah, 2
    je .receive_char

    cmp ah, 3
    je .get_status

    jmp .unsupported_func

.init_port: ; AH = 00h
    call serial_init
    call .do_get_status
    jmp .done

.send_char: ; AH = 01h
    ; AL = character
    ; DX = port (0)
    call serial_putc
    ; Return status - we assume success.
    mov ah, 0
    jmp .done

.receive_char: ; AH = 02h
    ; DX = port (0)
    call serial_getc
    ; Return status - we assume success.
    mov ah, 0
    jmp .done

.get_status: ; AH = 03h
    call .do_get_status
    jmp .done

.unsupported_port:
.unsupported_func:
    ; Set error flag in AH (e.g., bit 7)
    mov ah, 0x80
    
.done:
    pop si
    pop dx
    pop cx
    pop bx
    iret

.do_get_status:
    mov dx, SERIAL_PORT_LCR
    in al, dx
    mov ah, al
    mov dx, SERIAL_PORT_MCR
    in al, dx
    ret


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
    push dx
    push ax
    mov dx, SERIAL_PORT_LSR
.wait_tx:
    in  al, dx
    test al, 0x20
    jz  .wait_tx
    ; send char
    mov dx, SERIAL_PORT
    pop ax
    out dx, al
    pop dx
    ret

; ---------------------
; serial_getc: returns character in AL (polling)
; ---------------------
serial_getc:
    ; wait for Data Ready (LSR bit 0 = 0x01)
    push dx
    mov dx, SERIAL_PORT_LSR
.wait_rx:
    in  al, dx
    test al, 0x01
    jz  .wait_rx
    ; read received byte from RBR (0x3F8)
    mov dx, SERIAL_PORT
    in  al, dx
    pop dx
    ret

; ---------------------
; serial_peekc: returns character in AL if available, does not remove from buffer
; Carry flag set if character is available, clear if not
; ---------------------
serial_peekc:
    push dx
    mov dx, SERIAL_PORT_LSR
    in  al, dx
    test al, 0x01           ; Data Ready?
    jz  .no_char
    ; Data is ready, read from RBR but do not remove from buffer
    ; On 8250 UART, reading RBR removes the byte, so true peek is not possible.
    ; As a workaround, just signal availability and leave AL undefined.
    stc                     ; Set carry to indicate char available
    pop dx
    ret
.no_char:
    clc                     ; Clear carry to indicate no char
    pop dx
    ret