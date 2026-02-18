; this should go in "extended data area", but i'm lazy. 
; will use reserved 
DATA_MOUSE_DRIVER EQU 0xAC
DATA_MOUSE_BUFFER_COUNTER EQU 0xB0
DATA_MOUSE_BUFFER EQU 0xB1

mov ax, 0x40
mov es, ax
mov word [es:DATA_MOUSE_DRIVER], 0
mov word [es:DATA_MOUSE_DRIVER + 2], 0
mov byte [es:DATA_MOUSE_BUFFER_COUNTER], 0

int15_mouse:
    cmp al, 0x00
    je .activate_deactivate

    ; don't care

    ; cmp al, 0x01
    ; je .reset

    ; cmp al, 0x02
    ; je .set_sample_rate

    ; cmp al, 0x03
    ; je .set_resolution

    cmp al, 0x04
    je .get_type

    ; cmp al, 0x05
    ; je .init

    ; cmp al, 0x06
    ; je .extended_commands

    cmp al, 0x07
    je .set_driver_address

    ; cmp al, 0x08
    ; je .write_port

    ; cmp al, 0x09
    ; je .read_port

    jmp .done

.activate_deactivate:

    cmp bh, 0
    je .enable
    
    call .disable
    iret

.enable:
    mov al, 0xA8
    out 0x64, al
    iret

.disable:
    mov al, 0xA7
    out 0x64, al
    iret


.get_type:
    mov bh, 0x3 ; mouse
    iret

.set_driver_address:
    push ds
    mov ax, 0x40
    mov ds, ax

    mov word [ds:DATA_MOUSE_DRIVER], bx
    mov ax, es
    mov word [ds:DATA_MOUSE_DRIVER + 2], ax
    
    pop ds

    iret

.done:
    iret

irq12_handler:
    sti
    push es

    mov ax, 0x40
    mov es, ax

    ; read status
    in al, 0x64
    test al, 0x21
    jz .read_mouse_data

    jmp .done

.read_mouse_data:
    in al, 0x60

    mov ah, [es:DATA_MOUSE_BUFFER_COUNTER]
    mov bl, ah
    mov bh, 0
    add bx, DATA_MOUSE_BUFFER
    
    mov [es:bx], al

    inc ah

    mov [es:DATA_MOUSE_BUFFER_COUNTER], ah

    cmp ah, 3
    je .call_driver

    jmp .done

.call_driver:

    mov ax, [es:DATA_MOUSE_DRIVER]
    cmp ax, 0
    jne .do_call_driver

    jmp .done

.do_call_driver:

	xor ax, ax
	mov al, byte [es:DATA_MOUSE_BUFFER]
	push ax
	mov al, byte [es:DATA_MOUSE_BUFFER+1]
	push ax
	mov al, byte [es:DATA_MOUSE_BUFFER+2]
	push ax
	mov al, 0
	push ax

    call far [es:DATA_MOUSE_DRIVER]

    add	sp,0008h ; discard params

    mov ax, 0x40
    mov es, ax
    mov byte [es:DATA_MOUSE_BUFFER_COUNTER], 0

.done:
    mov	al, 0x20 ; signal PIC
	out	0x20, al

    pop es
    
    iret
