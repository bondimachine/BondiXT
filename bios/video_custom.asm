DATA_AREA_VIDEO_MODE EQU 0x49

init_video:
    ; set default video mode to 80x25 color text mode
    mov ax, 0x40
    mov es, ax
    mov byte [es:DATA_AREA_VIDEO_MODE], 0x03

;     mov dx, 0x3da
;     in al, dx ; reset the flip-flop by reading the input status register

;     mov dx, 0x3c0
;     mov si, atc80x25
;     mov cx, 20
;     xor bl, bl
;     cld
; .next_reg_atc:
;     mov al, bl
;     out dx, al
;     lodsb
;     out dx, al
;     inc bl
;     loop .next_reg_atc

; ; idk why people doesn't just include the 0x14 register in the atc80x25 array, but whatever, let's just write it here
;     mov al, 0x14
;     out dx, al
;     mov al, 0x00 ; disable overscan color (set to black)
;     out dx, al

;     mov  dx, 0x3c4
;     mov  ax, 0x0300
;     out  dx, ax
  
;     mov si, sequ80x25
;     mov cx, 4
;     xor bl, bl
;     cld
; .next_reg_sequ:
;     lodsb
;     mov ah, al
;     mov al, bl
;     out dx, ax
;     inc bl
;     loop .next_reg_sequ

;     mov dx, 0x3ce
;     mov si, grdc80x25
;     mov cx, 9
;     xor bl, bl
;     cld
; .next_reg_grdc:
;     lodsb
;     mov ah, al
;     mov al, bl
;     out dx, ax
;     inc bl
;     loop .next_reg_grdc

;     mov dx, 0x3c2
;     mov al, 0x67 
;     out dx, al
    
;     mov dx, 0x3D4
;     mov ax, 0x0011
;     out dx, ax

;     mov si, crtc80x25
;     mov cx, 0x19
;     xor bl, bl
; .next_reg:
;     lodsb
;     mov ah, al
;     mov al, bl
;     out dx, ax
;     inc bl
;     loop .next_reg

;     mov dx, 0x3c0
;     mov al, 0x20 ; unblank the screen
;     out dx, al

;     ; set font

;     xor ax, ax
;     mov es, ax
;     mov bx, 0x2596 ; offset of the 8x16 font in the bios rom
;     mov ax, 0xc000
;     mov  [es:0x010c], bx ;; INT 0x43
;     mov  [es:0x010e], ax

;     mov ax, 0xb800
;     mov es, ax
;     xor di, di
;     mov cx, 8
;     rep stosw

    ret


int10_handler:
    push cx
    push dx
    push si
    push es

    cmp ah, 0x00         
    je .set_video_mode

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
    mov al, 0xA ; high res text mode, output enabled
    jmp .set_save_and_done

.set_mode_cga:
    mov dx, 0x3D8
    mov al, 0x6 ; low res graphics mode, output enabled
    jmp .set_save_and_done

.set_mode_cga_high_res:
    mov dx, 0x3D8
    mov al, 0xE ; high res graphics mode, output enabled
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
    mov byte [es:DATA_AREA_VIDEO_MODE], al
    jmp .done

.set_palette_cga:
    mov dx, 0x3D9
    mov al, 0x1
    and al, bl
    rol al, 5
    out dx, al
    jmp .done

.teletype_output:
    ; for the moment we still send teletype output to serial port
    call serial_putc
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

.done:
    pop es
    pop si
    pop dx
    pop cx
    iret

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
