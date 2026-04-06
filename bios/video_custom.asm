DATA_AREA_VIDEO_MODE EQU 0x49
DATA_AREA_CURSOR_X EQU 0x50
DATA_AREA_CURSOR_Y EQU 0x51
DATA_AREA_VIDEO_CGA_PALETTE equ	66h

init_video:
    ; set default video mode to 80x25 color text mode
    mov ax, 0x40
    mov es, ax
    mov byte [es:DATA_AREA_VIDEO_MODE], 0x03

    mov byte [es:DATA_AREA_CURSOR_X], 0
    mov byte [es:DATA_AREA_CURSOR_Y], 0

    mov dx, 0x3D8
    mov al, 0b01001 ; high res text mode, output enabled
    out dx, al

    ret


int10_handler:
    push bx
    push cx
    push dx
    push si
    push es

    cmp ah, 0x00         
    je .set_video_mode

    cmp ah, 0x02
    je .set_cursor_position

    cmp ah, 0x03
    je .query_cursor_position

    cmp ah, 0x6
    je .scroll_up

    cmp ah, 0x6
    je .scroll_dn

    cmp ah, 0x09
    je .write_character_attribute

    cmp ah, 0x0a
    je .write_character

    cmp ah, 0xb
    je .set_palette_cga

    cmp ah, 0x0e          
    je .teletype_output

    cmp ah, 0x0f
    je .read_video_mode

    cmp ah, 0x12          
    je .special_functions

    cmp ah, 0x1a
    je .dcc

    jmp .done

.set_video_mode:

    mov ah, al ; save requested mode in ah for later use in special functions
    cmp al, 0x02 ; 80x25 monochrome text mode
    je .set_mode_text

    cmp al, 0x03 ; 80x25 color text mode
    je .set_mode_text

    cmp al, 0x04 ; 320x200 4-color graphics mode
    je .set_mode_cga

    cmp al, 0x05 ; 320x200 4-color graphics mode
    je .set_mode_cga

    cmp al, 0x06 ; 640x200 monochrome graphics mode
    je .set_mode_cga_high_res

    cmp al, 0x10 ; 640x200 16-color graphics mode
    je .set_mode_ega

    cmp al, 0x12 ; 640x480 16-color graphics mode
    je .set_mode_vga

    cmp al, 0x13 ; 320x200 256-color graphics mode
    je .set_mode_mcga

    jmp .done

.set_mode_text:
    mov dx, 0x3D8
    mov al, 0b01001 ; high res text mode, output enabled
    jmp .set_save_and_done

.set_mode_cga:
    mov dx, 0x3D8
    mov al, 0b01010 ; low res graphics mode, output enabled
    jmp .set_save_and_done

.set_mode_cga_high_res:
    mov dx, 0x3D8
    mov al, 0b11010 ; high res graphics mode, output enabled
    jmp .set_save_and_done

.set_mode_ega:
    mov dx, 0x3c2
    mov al, 0xa3 ; some miscellaneous register magic value to detect high res ega
    jmp .set_save_and_done

.set_mode_vga:
    mov dx, 0x3c2
    mov al, 0xe3 ; some miscellaneous register magic value to detect high res vga
    jmp .set_save_and_done

.set_mode_mcga:
    mov dx, 0x3c2
    mov al, 0xf ; else to enforce mcga mode
    jmp .set_save_and_done

.set_save_and_done:
    out dx, al
    mov dx, 0x40
    mov es, dx
    mov byte [es:DATA_AREA_VIDEO_MODE], ah
    jmp .done

.set_palette_cga:
    mov dx, 0x40
    mov es, dx
    mov al, byte [es:DATA_AREA_VIDEO_CGA_PALETTE]

    cmp bh, 0
    jne .set_palette

    ; set background and intensity bits from bl
    and bl, 0b00011111 ; 
    and al, 0b11100000 ; clear lower bits. keep palette bit 
    or al, bl ; set background color and intensity in al
    mov byte [es:DATA_AREA_VIDEO_CGA_PALETTE], al
    jmp .save_palette_and_done

.set_palette:
    and al, 0b00011111 ;
    test bl, 01h
	jz	.save_palette_and_done
    or al, 0b00100000 ; set the palette bit (bit 5) if bit 0 of bl is set (palette 1)

.save_palette_and_done:
    mov byte [es:DATA_AREA_VIDEO_CGA_PALETTE], al
    mov dx, 0x3D9
    out dx, al
    jmp .done

.read_video_mode:
    mov ax, 0x40
    mov es, ax
    mov al, [es:DATA_AREA_VIDEO_MODE]
    mov ah, 80
    mov bh, 0
    jmp .done

; Comes from this excerpt:
;
; Set AX=1200, BL=32 and call INT 10. If AL returns 12h, you have a VGA. 
; If not, set AH=12, BL=10 and call INT 10 again. If BL returns 0,1,2,3, you
; have an EGA with 64,128,192,256K memory. If not, set AH=0F and call INT; 
; 10 a third time. If AL is 7, you have an MDA (original monochrome 
; adapter) or Hercules; if not, you have a CGA.
; 

.special_functions:
    cmp bl, 0x10
    je .get_ega_info

    cmp bl, 0x32
    je .enable_access_to_video

    jmp .done

.get_ega_info:
    mov bx, 0 ; color, 64kb
    mov cx, 0 ; no features
    jmp .done

.enable_access_to_video:
    mov al, 0x12 ; yes, we are VGA
    jmp .done

; this one comes from Turbo Pascal graphics mode detection
.dcc:
    cmp al, 0
    jne .done

    mov al, 0x1a
    mov bl, 0x8 ; yes, we are VGA
    jmp .done

.set_cursor_position:

    mov ax, 0x40
    mov es, ax
    mov word [es:DATA_AREA_CURSOR_X], dx

.update_cursor_and_done:

    mov al, dh
    mov cl, 160
    mul cl

    mov ch, 0
    mov cl, dl
    shl cx, 1
    add ax, cx
    mov cx, ax

    mov dx, 0x3d4
    mov al, 0x0e
    out dx, al

    inc dx
    mov al, ch
    out dx, al

    dec dx
    mov al, 0x0f
    out dx, al

    inc dx
    mov al, cl
    out dx, al

    jmp .done


.query_cursor_position:
    mov ax, 0x40
    mov es, ax
    mov dx, word [es:DATA_AREA_CURSOR_X]
    jmp .done

.scroll_up:
    neg al

.scroll_dn:
    mov dx, 0x3df
    out dx, al
    jmp .done

.write_character_attribute:

    call calculate_video_offset_es_si
    mov ah, bl
.write_next_character_attribute:    
    mov word [es:si], ax      ; character and attribute
    call serial_putc
    inc si
    inc si
    dec cx
    jnz .write_next_character_attribute ; write character and attribute cx times
    jmp .done

.write_character:

    call calculate_video_offset_es_si

.write_next_character:
    mov byte [es:si], al      ; character
    call serial_putc
    inc si
    inc si
    dec cx
    jnz .write_next_character ; write character cx times, attribute is unchanged
    jmp .done

.teletype_output:
    ; for debugging
    call serial_putc

    ; Handle carriage return (CR, 0x0D)
    cmp al, 0x0D
    je .teletype_cr

    ; Handle line feed (LF, 0x0A)
    cmp al, 0x0A
    je .teletype_lf

    ; Handle backspace (BS, 0x08)
    cmp al, 0x8
    je .teletype_bs

    mov bx, ax ; save character in bx for later use in text mode update

    call calculate_video_offset_es_si
    mov byte [es:si], bl      ; character
    mov byte [es:si+1], 0x07  ; attribute (white on black)

    ; Increment cursor X
    mov ax, 0x40
    mov es, ax
    inc byte [es:DATA_AREA_CURSOR_X]

    ; Check if X reached 80
    cmp byte [es:DATA_AREA_CURSOR_X], 80
    jne .teletype_update_hw

    ; Reset X to 0 and increment Y
    mov byte [es:DATA_AREA_CURSOR_X], 0
    inc byte [es:DATA_AREA_CURSOR_Y]

.check_scroll_and_update_cursor:
    ; Check if Y reached 25
    cmp byte [es:DATA_AREA_CURSOR_Y], 25
    jne .teletype_update_hw

    ; Scroll up: set Y to 24 and scroll
    mov byte [es:DATA_AREA_CURSOR_Y], 24
    mov al, -1
    mov dx, 0x3df
    out dx, al

.teletype_update_hw:
    mov dx, word [es:DATA_AREA_CURSOR_X]
    jmp .update_cursor_and_done

.teletype_cr:
    mov ax, 0x40
    mov es, ax
    mov byte [es:DATA_AREA_CURSOR_X], 0
    jmp .teletype_update_hw

.teletype_lf:
    mov ax, 0x40
    mov es, ax
    inc byte [es:DATA_AREA_CURSOR_Y]
    jmp .check_scroll_and_update_cursor

    jmp .done

.teletype_bs:
    mov ax, 0x40
    mov es, ax
    cmp byte [es:DATA_AREA_CURSOR_X], 0
    je .done ; if we're at the beginning of the line, do nothing

    dec byte [es:DATA_AREA_CURSOR_X]
    jmp .teletype_update_hw

.done:

    pop es
    pop si
    pop dx
    pop cx
    pop bx

    iret

calculate_video_offset_es_si:
    push ax
    push cx

    ; Write character to video memory
    mov ax, 0x40
    mov es, ax
    mov dl, [es:DATA_AREA_CURSOR_X]
    mov dh, [es:DATA_AREA_CURSOR_Y]

    ; Calculate offset: (row * 80 + col) * 2
    mov ah, 0
    mov al, dh
    mov cl, 160
    mul cl

    mov ch, 0
    mov cl, dl
    shl cx, 1
    add ax, cx
    mov si, ax

    ; Write to video memory at B8000
    mov ax, 0xb800
    mov es, ax

    pop cx ; restore count to cx
    pop ax ; restore character to al

    ret

; atc80x25:
;     db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x0c, 0x00, 0x0f, 0x08

; sequ80x25:
;     db 0x00, 0x03, 0x00, 0x02

; crtc80x25:
; 	db 0x5f, 0x4f, 0x50, 0x82, 0x55, 0x81, 0xbf, 0x1f, 0x00, 0x4f, 0x0d, 0x0e, 0x00, 0x00, 0x00, 0x00, 0x9c, 0x8e, 0x8f, 0x28, 0x1f, 0x96, 0xb9, 0xa3, 0xff

; grdc80x25:
;     db 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0e, 0x0f, 0xff

; hello:
;     db 0x07, 'B', 0x07, 'o', 0x07, 'n', 0x07, 'd', 0x07, 'i', 0x07, 'V', 0x07, 'G', 0x07, 'A'
