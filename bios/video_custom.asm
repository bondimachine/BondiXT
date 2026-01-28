DATA_AREA_VIDEO_MODE EQU 0x49

; set default video mode to 80x25 color text mode
mov ax, 0x40
mov es, ax
mov byte [es:DATA_AREA_VIDEO_MODE], 0x03

int10_handler:
    pusha

    cmp ah, 0x00         
    je .set_video_mode

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
    popa
    iret
