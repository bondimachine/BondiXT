BIOS_DATA_AREA_USE_KEYBOARD EQU 0x12 ; this is some pcjr crap, using for something useful
BIOS_DATA_AREA_SHIFT_KEYS EQU 0x17
BIOS_DATA_AREA_BUFFER_HEAD EQU 0x1a
BIOS_DATA_AREA_BUFFER_TAIL EQU 0x1c
BIOS_DATA_AREA_BUFFER EQU 0x1e

init_keyboard:
    mov ax, 0x40
    mov es, ax

    %ifdef PS2_KEYBOARD

        mov al, 0xAA
        out 0x64, al
        in al, 0x60
        cmp al, 0x55
        jne .no_keyboard

        ; Enable Set 2 -> Set 1 scancode translation in the 8042 controller
        mov al, 0x20               ; Command: read controller config byte
        out 0x64, al
        in al, 0x60                ; Read the config byte
        or al, 0x40                ; Set bit 6 = translation enabled
        push ax
        mov al, 0x60               ; Command: write controller config byte
        out 0x64, al
        pop ax
        out 0x60, al               ; Write modified config byte

        mov byte [es:BIOS_DATA_AREA_USE_KEYBOARD], 1
        mov word [es:BIOS_DATA_AREA_BUFFER_HEAD], BIOS_DATA_AREA_BUFFER
        mov word [es:BIOS_DATA_AREA_BUFFER_TAIL], BIOS_DATA_AREA_BUFFER
        mov byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0

        mov al, 1
        jmp .keyboard_init_done


    %endif

.no_keyboard:
    mov byte [es:BIOS_DATA_AREA_USE_KEYBOARD], 0
    mov al, 0

.keyboard_init_done:
    ret

int16_handler:
    push es
    push bx
    mov bx, 0x40
    mov es, bx

    test byte [es:BIOS_DATA_AREA_USE_KEYBOARD], 1
    jnz .use_keyboard

    cmp ah, 0x00
    je .read_keypress

    cmp ah, 0x01
    je .preview_key

    jmp .done

.use_keyboard:
    cmp ah, 0x00
    je .read_keypress_keyboard

    cmp ah, 0x01
    je .preview_key_keyboard

    cmp ah, 0x02
    je .get_status

    jmp .done
    

.read_keypress:
    call serial_getc
    jmp .done

.preview_key:
    call serial_peekc
    jmp .done

.read_keypress_keyboard:
    ; check for key in buffer, if available, return it
    ; otherwise try to fetch a key from keyboard.
    ; Blocking: loops until a key is available.
.read_kb_loop:
    cli
    mov bx, [es:BIOS_DATA_AREA_BUFFER_HEAD]
    cmp bx, [es:BIOS_DATA_AREA_BUFFER_TAIL]
    jne .consume_from_buffer
    sti

    ; Buffer empty - poll keyboard controller
    in al, 0x64
    test al, 0x01              ; Output buffer full? (key available?)
    jz .read_kb_loop           ; No, keep polling

    ; Read scancode and store in buffer
    call .fetch_key_to_buffer
    jmp .read_kb_loop          ; Loop back to read from buffer

.consume_from_buffer:
    ; BX = buffer head pointer, read the word and advance head
    mov ax, [es:bx]
    add bx, 2
    cmp bx, BIOS_DATA_AREA_BUFFER + 32
    jb .no_wrap_consume
    mov bx, BIOS_DATA_AREA_BUFFER
.no_wrap_consume:
    mov [es:BIOS_DATA_AREA_BUFFER_HEAD], bx
    sti
    jmp .done

.preview_key_keyboard:
    ; check for key in buffer, if available, return it (without consuming)
    ; otherwise try to fetch a key from keyboard.
    ; if one available, save it to buffer and also return it.
    ; Non-blocking: returns with ZF=1 if no key.
    cli
    mov bx, [es:BIOS_DATA_AREA_BUFFER_HEAD]
    cmp bx, [es:BIOS_DATA_AREA_BUFFER_TAIL]
    jne .peek_from_buffer
    sti

    ; Buffer empty - check keyboard controller (non-blocking)
    in al, 0x64
    test al, 0x01              ; Output buffer full?
    jz .no_key_available       ; No key, return ZF=1

    ; Read scancode and store in buffer
    call .fetch_key_to_buffer

    ; Now peek from buffer
    cli
    mov bx, [es:BIOS_DATA_AREA_BUFFER_HEAD]
    cmp bx, [es:BIOS_DATA_AREA_BUFFER_TAIL]
    je .no_key_sti             ; Break code was discarded, no key

.peek_from_buffer:
    ; BX = buffer head pointer, read word but do NOT advance head
    mov ax, [es:bx]
    sti
    ; Clear ZF to indicate key is available
    test ax, 0xFFFF
    jmp .done

.no_key_sti:
    sti
.no_key_available:
    ; Set ZF=1 to indicate no key available
    xor ax, ax
    jmp .done


.get_status:
    mov ax, [es:BIOS_DATA_AREA_SHIFT_KEYS]

.done:
    pop bx
    pop es
    retf 2 ; // instead of iret to overwrite flags.

; -----------------------------------------------------------------------
; .fetch_key_to_buffer: read scancode from port 0x60, translate to ASCII,
; and store word (AH=scancode, AL=ASCII) in BIOS keyboard buffer.
; Handles modifier keys by updating BIOS_DATA_AREA_SHIFT_KEYS.
; Assumes ES = 0x40.
;
; BIOS_DATA_AREA_SHIFT_KEYS bit layout:
;   Bit 0 = Right Shift pressed
;   Bit 1 = Left Shift pressed
;   Bit 2 = Ctrl pressed
;   Bit 3 = Alt pressed
;   Bit 4 = Scroll Lock active
;   Bit 5 = Num Lock active
;   Bit 6 = Caps Lock active
;   Bit 7 = Insert active
; -----------------------------------------------------------------------
.fetch_key_to_buffer:
    in al, 0x60                ; Read scancode from keyboard data port

    ; --- Handle break codes (key releases) ---
    test al, 0x80
    jz .make_code

    ; Break code: strip bit 7 to get the base scancode
    and al, 0x7F

    ; Check if it's a modifier release
    cmp al, 0x2A               ; Left Shift release?
    jne .chk_brk_rshift
    and byte [es:BIOS_DATA_AREA_SHIFT_KEYS], ~0x02
    ret
.chk_brk_rshift:
    cmp al, 0x36               ; Right Shift release?
    jne .chk_brk_ctrl
    and byte [es:BIOS_DATA_AREA_SHIFT_KEYS], ~0x01
    ret
.chk_brk_ctrl:
    cmp al, 0x1D               ; Ctrl release?
    jne .chk_brk_alt
    and byte [es:BIOS_DATA_AREA_SHIFT_KEYS], ~0x04
    ret
.chk_brk_alt:
    cmp al, 0x38               ; Alt release?
    jne .fetch_done
    and byte [es:BIOS_DATA_AREA_SHIFT_KEYS], ~0x08
    ret

    ; --- Handle make codes (key presses) ---
.make_code:
    ; Check if it's a modifier make
    cmp al, 0x2A               ; Left Shift press?
    jne .chk_mk_rshift
    or byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x02
    ret
.chk_mk_rshift:
    cmp al, 0x36               ; Right Shift press?
    jne .chk_mk_ctrl
    or byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x01
    ret
.chk_mk_ctrl:
    cmp al, 0x1D               ; Ctrl press?
    jne .chk_mk_alt
    or byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x04
    ret
.chk_mk_alt:
    cmp al, 0x38               ; Alt press?
    jne .chk_mk_capslock
    or byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x08
    ret
.chk_mk_capslock:
    cmp al, 0x3A               ; Caps Lock press?
    jne .regular_key
    ; Toggle Caps Lock bit
    xor byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x40
    ret

.regular_key:
    ; AL = scancode (make code). Translate to ASCII.
    push bx
    mov ah, al                 ; AH = scancode
    xor bh, bh
    mov bl, al                 ; BX = scancode index
    cmp bl, SCANCODE_TABLE_LEN
    jae .no_ascii

    ; Determine which table to use based on Shift / Caps Lock state
    mov si, scancode_table             ; Default: unshifted
    test byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x03  ; Either Shift pressed?
    jnz .use_shifted
    ; No Shift - check Caps Lock for letter keys
    test byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x40  ; Caps Lock active?
    jz .do_lookup
    ; Caps Lock on: only shift letters (scancodes 0x10-0x19, 0x1E-0x26, 0x2C-0x32)
    cmp bl, 0x10
    jb .do_lookup
    cmp bl, 0x19
    jbe .use_shifted
    cmp bl, 0x1E
    jb .do_lookup
    cmp bl, 0x26
    jbe .use_shifted
    cmp bl, 0x2C
    jb .do_lookup
    cmp bl, 0x32
    jbe .use_shifted
    jmp .do_lookup

.use_shifted:
    mov si, scancode_table_shifted

.do_lookup:
    ; Use CS segment override to read the table (code lives in ROM)
    mov al, [cs:si + bx]

    ; If Ctrl is held, convert to control character (AND 0x1F)
    test byte [es:BIOS_DATA_AREA_SHIFT_KEYS], 0x04  ; Ctrl pressed?
    jz .store_key
    and al, 0x1F               ; Ctrl+A=0x01, Ctrl+C=0x03, etc.
    jmp .store_key

.no_ascii:
    xor al, al                 ; No ASCII for this scancode

.store_key:
    ; AH = scancode, AL = ASCII. Store in circular buffer.
    mov bx, [es:BIOS_DATA_AREA_BUFFER_TAIL]
    mov [es:bx], ax
    add bx, 2
    cmp bx, BIOS_DATA_AREA_BUFFER + 32
    jb .no_wrap_store
    mov bx, BIOS_DATA_AREA_BUFFER
.no_wrap_store:
    ; Check for buffer full (tail would equal head)
    cmp bx, [es:BIOS_DATA_AREA_BUFFER_HEAD]
    je .buffer_full            ; Drop the key if buffer is full
    mov [es:BIOS_DATA_AREA_BUFFER_TAIL], bx
.buffer_full:
    pop bx
.fetch_done:
    ret

; -----------------------------------------------------------------------
; Scancode to ASCII lookup table (Set 1, US QWERTY, unshifted)
; Index = scancode, Value = ASCII character (0 = no mapping)
; -----------------------------------------------------------------------
scancode_table:
    db 0        ; 0x00 - (none)
    db 0x1B     ; 0x01 - Escape
    db '1'      ; 0x02
    db '2'      ; 0x03
    db '3'      ; 0x04
    db '4'      ; 0x05
    db '5'      ; 0x06
    db '6'      ; 0x07
    db '7'      ; 0x08
    db '8'      ; 0x09
    db '9'      ; 0x0A
    db '0'      ; 0x0B
    db '-'      ; 0x0C
    db '='      ; 0x0D
    db 0x08     ; 0x0E - Backspace
    db 0x09     ; 0x0F - Tab
    db 'q'      ; 0x10
    db 'w'      ; 0x11
    db 'e'      ; 0x12
    db 'r'      ; 0x13
    db 't'      ; 0x14
    db 'y'      ; 0x15
    db 'u'      ; 0x16
    db 'i'      ; 0x17
    db 'o'      ; 0x18
    db 'p'      ; 0x19
    db '['      ; 0x1A
    db ']'      ; 0x1B
    db 0x0D     ; 0x1C - Enter
    db 0        ; 0x1D - Left Ctrl
    db 'a'      ; 0x1E
    db 's'      ; 0x1F
    db 'd'      ; 0x20
    db 'f'      ; 0x21
    db 'g'      ; 0x22
    db 'h'      ; 0x23
    db 'j'      ; 0x24
    db 'k'      ; 0x25
    db 'l'      ; 0x26
    db ';'      ; 0x27
    db 0x27     ; 0x28 - Single quote
    db '`'      ; 0x29
    db 0        ; 0x2A - Left Shift
    db 0x5C     ; 0x2B - Backslash
    db 'z'      ; 0x2C
    db 'x'      ; 0x2D
    db 'c'      ; 0x2E
    db 'v'      ; 0x2F
    db 'b'      ; 0x30
    db 'n'      ; 0x31
    db 'm'      ; 0x32
    db ','      ; 0x33
    db '.'      ; 0x34
    db '/'      ; 0x35
    db 0        ; 0x36 - Right Shift
    db '*'      ; 0x37 - Keypad *
    db 0        ; 0x38 - Left Alt
    db ' '      ; 0x39 - Space
SCANCODE_TABLE_LEN EQU $ - scancode_table

; -----------------------------------------------------------------------
; Scancode to ASCII lookup table (Set 1, US QWERTY, SHIFTED)
; Same indexing as above, with shifted characters
; -----------------------------------------------------------------------
scancode_table_shifted:
    db 0        ; 0x00 - (none)
    db 0x1B     ; 0x01 - Escape
    db '!'      ; 0x02 - Shift+1
    db '@'      ; 0x03 - Shift+2
    db '#'      ; 0x04 - Shift+3
    db '$'      ; 0x05 - Shift+4
    db '%'      ; 0x06 - Shift+5
    db '^'      ; 0x07 - Shift+6
    db '&'      ; 0x08 - Shift+7
    db '*'      ; 0x09 - Shift+8
    db '('      ; 0x0A - Shift+9
    db ')'      ; 0x0B - Shift+0
    db '_'      ; 0x0C - Shift+-
    db '+'      ; 0x0D - Shift+=
    db 0x08     ; 0x0E - Backspace
    db 0x09     ; 0x0F - Tab
    db 'Q'      ; 0x10
    db 'W'      ; 0x11
    db 'E'      ; 0x12
    db 'R'      ; 0x13
    db 'T'      ; 0x14
    db 'Y'      ; 0x15
    db 'U'      ; 0x16
    db 'I'      ; 0x17
    db 'O'      ; 0x18
    db 'P'      ; 0x19
    db '{'      ; 0x1A - Shift+[
    db '}'      ; 0x1B - Shift+]
    db 0x0D     ; 0x1C - Enter
    db 0        ; 0x1D - Left Ctrl
    db 'A'      ; 0x1E
    db 'S'      ; 0x1F
    db 'D'      ; 0x20
    db 'F'      ; 0x21
    db 'G'      ; 0x22
    db 'H'      ; 0x23
    db 'J'      ; 0x24
    db 'K'      ; 0x25
    db 'L'      ; 0x26
    db ':'      ; 0x27 - Shift+;
    db '"'      ; 0x28 - Shift+'
    db '~'      ; 0x29 - Shift+`
    db 0        ; 0x2A - Left Shift
    db '|'      ; 0x2B - Shift+backslash
    db 'Z'      ; 0x2C
    db 'X'      ; 0x2D
    db 'C'      ; 0x2E
    db 'V'      ; 0x2F
    db 'B'      ; 0x30
    db 'N'      ; 0x31
    db 'M'      ; 0x32
    db '<'      ; 0x33 - Shift+,
    db '>'      ; 0x34 - Shift+.
    db '?'      ; 0x35 - Shift+/
    db 0        ; 0x36 - Right Shift
    db '*'      ; 0x37 - Keypad *
    db 0        ; 0x38 - Left Alt
    db ' '      ; 0x39 - Space
