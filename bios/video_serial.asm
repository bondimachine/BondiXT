init_video:
    ret

int10_handler:
    pusha

    cmp ah, 0x0e          
    je .teletype_output

    cmp ah, 0x0f
    je .read_video_mode

    jmp .done


.teletype_output:
    call serial_putc
    jmp .done

.read_video_mode:
    mov al, 03h ; 80x25 color text mode
    mov ah, 80
    mov bh, 0
    jmp .done

.done:
    popa
    iret
