int16_handler:
    cmp ah, 0x00
    je .read_keypress

    cmp ah, 0x01
    je .preview_key

    jmp .done

.read_keypress:
    call serial_getc
    jmp .done

.preview_key:
    call serial_peekc

.done:
    retf 2 ; // instead of iret to overwrite flags.
