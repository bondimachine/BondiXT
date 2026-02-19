; this should go in "extended data area", but i'm lazy. 
; will use reserved 
DATA_MOUSE_DRIVER EQU 0xAC
DATA_MOUSE_BUFFER_COUNTER EQU 0xB0
DATA_MOUSE_BUFFER EQU 0xB1

init_mouse:
    mov ax, 0x40
    mov es, ax
    mov word [es:DATA_MOUSE_DRIVER], 0
    mov word [es:DATA_MOUSE_DRIVER + 2], 0
    mov byte [es:DATA_MOUSE_BUFFER_COUNTER], 0
    ret

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

    cmp al, 0x05
    je .init

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

    cmp bh, 1
    je .enable
    
    call .disable
    jmp .done

.enable:
    call wait_ps2_input
    mov al, 0xA8
    out 0x64, al
    jmp .done

.disable:
    call wait_ps2_input
    mov al, 0xA7
    out 0x64, al
    jmp .done

.get_type:
    mov bh, 0x0 ; mouse
    jmp .done

.init:

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

    jmp .done

.set_driver_address:
    push ds
    mov ax, 0x40
    mov ds, ax

    mov word [ds:DATA_MOUSE_DRIVER], bx
    mov ax, es
    mov word [ds:DATA_MOUSE_DRIVER + 2], ax
    
    pop ds

.done:
    clc
    mov ah, 0

    retf 2


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

irq12_handler:
    sti
    push es

    mov ax, 0x40
    mov es, ax

    ; read status
    in al, 0x64
    test al, 0x21
    jnz .read_mouse_data

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
