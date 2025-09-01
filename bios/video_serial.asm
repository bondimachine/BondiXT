int10_handler:
    pusha

    cmp ah, 0x0E          ; check if teletype function
    jne .done

    call serial_putc

.done:
    popa
    iret

estoy    db "Estoy!", 13, 10, 13, 10, 0
