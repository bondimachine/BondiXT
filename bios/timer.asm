DATA_AREA_TICKS_LO	equ	6Ch	; word - timer ticks - low word
DATA_AREA_TICKS_HI	equ	6Eh	; word - timer ticks - high word
DATA_AREA_NEW_DAY	equ	70h	; byte - 1 = new day flag

init_timer:

    mov ax, 0x40
    mov es, ax
    mov	word [es:DATA_AREA_TICKS_LO], 0
	mov	word [es:DATA_AREA_TICKS_HI], 0
	mov	byte [es:DATA_AREA_NEW_DAY], 0	; read new_day to al

    mov	al, 0x36 ; channel 0, LSB & MSB, mode 3, binary
	out	0x43, al
	mov	al, 0
	out	0x40, al
	out	0x40, al    

    mov	al,13h			; ICW1 - edge triggered, single, ICW4
	out	0x20, al
	mov	al, 0x08			; ICW2 - interrupt vector offset = 8
	out	0x21, al
	mov	al, 0x09			; ICW4 - buffered mode, 8086/8088
	out	0x21, al
        
    ret

int1Ah_handler:

    push ax
    push es
    
    mov ax, 0x40
    mov es, ax

    pop ax

    cmp ah, 0x00         
    je .read_ticks

    cmp ah, 0x01
    je .set_ticks

    jmp .done

.read_ticks:
    mov	dx,word [es:DATA_AREA_TICKS_LO]
	mov	cx,word [es:DATA_AREA_TICKS_HI]
	mov	al,byte [es:DATA_AREA_NEW_DAY]
	mov	byte [es:DATA_AREA_NEW_DAY], 0
    jmp .done

.set_ticks:
    mov	word [es:DATA_AREA_TICKS_LO], dx
    mov	word [es:DATA_AREA_TICKS_HI], cx
    mov	byte [es:DATA_AREA_NEW_DAY], 0
    jmp .done

.done:
    pop es
    iret

irq0_handler:
    push ax
    push es
    mov ax, 0x40
    mov es, ax

	inc	word [es:DATA_AREA_TICKS_LO]
	jnz	.2
	inc	word [es:DATA_AREA_TICKS_HI]
.2:
	cmp	word [es:DATA_AREA_TICKS_HI],18h	; 1573042 ticks in one day
	jnz	.3			; which is 65536 * 24 + 178 or
	cmp	word [es:DATA_AREA_TICKS_LO],0B2h	; 10000h * 18h + 0B2h
	jnz	.3
	mov	word [es:DATA_AREA_TICKS_HI],0
	mov	word [es:DATA_AREA_TICKS_LO],0
	mov	byte [es:DATA_AREA_NEW_DAY],1
.3:
	int	1Ch			; User timer interrupt
    mov	al, 0x20 ; signal PIC
	out	0x20, al

    pop es
    pop ax
    iret


beep:
	push ax
    push cx

	mov	al, 0xB6		; set PIC channel 2 to mode 3
	out	0x43, al

	mov	ax, 1491		; approximately 800 Hz
	out	0x42, al		; load divisor's low byte to PIC
	mov	al, ah
	out	0x42, al		; load divisor's high byte to PIC

    mov al,  0x3		; turn on speaker (we don't have a PPI here, no need to read first)
    out	0x61, al

    mov bx, 4
.outer:
	mov	cx, 0xFFFF		; ~0.2 second delay
.inner:
	dec	cx
	jnz	.inner
    dec bx
    jnz .outer

    mov al, 0                ; turn off speaker
	out	0x61, al

	pop cx
    pop	ax
	ret