int16_handler:
    push dx

    cmp ah, 0x00          ; read key press
    jne .done

    call serial_getc

.done:
    pop dx
    iret
