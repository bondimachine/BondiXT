PORT EQU 0x3F8           ; COM1 base port
PORT_IER        EQU PORT + 1       ; Interrupt Enable Register
PORT_LCR        EQU PORT + 3       ; Line Control Register
PORT_MCR        EQU PORT + 4       ; Modem Control Register
PORT_LSR        EQU PORT + 5       ; Line Status Register
PORT_DIV_LOW    EQU PORT + 0       ; Divisor Latch Low Byte (when DLAB=1)
PORT_DIV_HIGH   EQU PORT + 1       ; Divisor Latch High Byte (when DLAB=1)

; For 115200 baud with a typical 1.8432MHz UART clock:
; Divisor = 1.8432MHz / (16 * 115200) = 1
BAUD_DIVISOR    EQU 1

; --- Code ---

section .text
_start:

    ; Initialize serial port
    mov dx, PORT_LCR        ; Line Control Register
    mov al, 0x80            ; Enable DLAB (set baud rate divisor)
    out dx, al

    mov dx, PORT_DIV_LOW    ; Divisor Latch Low Byte
    mov al, BAUD_DIVISOR
    out dx, al

    mov dx, PORT_DIV_HIGH   ; Divisor Latch High Byte
    mov al, 0
    out dx, al

    mov dx, PORT_LCR        ; Line Control Register
    mov al, 0x03            ; 8 bits, no parity, one stop bit
    out dx, al

    mov dx, PORT_MCR        ; Modem Control Register
    mov al, 0x03            ; RTS and DTR set
    out dx, al

    mov ax, cs
    mov ds, ax             ; DS = CS = donde cargó la BIOS = 0xF000
    mov si, msg            ; Pointer to message
    mov dx, PORT

.print_char:
    lodsb                   ; Load next character
    test al, al             ; Check for null terminator
    jz .done
    mov cl, al              ; Save character to send in cl

.wait_lsr:
    mov dx, (PORT_LSR)      ; Line Status Register
    in al, dx               ; Read Line Status Register (LSR)
    test al, 0x20           ; Check if Transmitter Holding Register Empty
    jz .wait_lsr

    mov dx, PORT            ; Data port
    mov al, cl              ; Load character to send
    out dx, al              ; Write character

    jmp .print_char

.done:
    hlt
    jmp .done

; --- Data ---
msg    db "Hola Gaston!", 0

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp _start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0    