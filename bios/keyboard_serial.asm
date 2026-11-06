; -----------------------------------------------------------------------
; Keyboard: 8042 (port 60h/64h) keyboard with Set 1 (translated) scancodes,
; or serial input when no keyboard is detected.
;
; All scancode handling lives in kb_service, which drains the controller
; and translates into the BIOS buffer. It is shared by the IRQ1 handler
; (INT 9) and by INT 16h, which also polls the controller, so keys still
; arrive if IRQ1 is not delivered.
; -----------------------------------------------------------------------

BIOS_DATA_AREA_USE_KEYBOARD EQU 0x12 ; this is some pcjr crap, using for something useful
BDA_KB_FLAG     EQU 0x17    ; shift / lock state
BDA_KB_FLAG_1   EQU 0x18    ; keys held
BDA_ALT_INPUT   EQU 0x19    ; Alt + keypad number entry
BDA_BUF_HEAD    EQU 0x1A
BDA_BUF_TAIL    EQU 0x1C
BDA_BUF         EQU 0x1E
BDA_BIOS_BREAK  EQU 0x71
BDA_RESET_FLAG  EQU 0x72
BDA_BUF_START   EQU 0x80
BDA_BUF_END     EQU 0x82
BDA_KB_FLAG_3   EQU 0x96    ; E0/E1 prefix, right Ctrl/Alt
BDA_KB_FLAG_2   EQU 0x97    ; LEDs

; BDA_KB_FLAG
KB_RSHIFT   EQU 0x01
KB_LSHIFT   EQU 0x02
KB_CTRL     EQU 0x04
KB_ALT      EQU 0x08
KB_SCROLL   EQU 0x10
KB_NUM      EQU 0x20
KB_CAPS     EQU 0x40
KB_INS      EQU 0x80
; BDA_KB_FLAG_1 (lock bits are the same as in BDA_KB_FLAG: "held")
KB1_LCTRL   EQU 0x01
KB1_LALT    EQU 0x02
KB1_PAUSE   EQU 0x08
; BDA_KB_FLAG_3
KB3_E1      EQU 0x01
KB3_E0      EQU 0x02
KB3_RCTRL   EQU 0x04
KB3_RALT    EQU 0x08
; BDA_KB_FLAG_2
KB2_LEDS    EQU 0x07
KB2_BUSY    EQU 0x40

; Timeouts are poll counts sized for a 4.77 MHz 8088: one poll of the
; status port (in / test / jnz / loop) takes ~45 cycles, so 10600 polls are
; ~0.1 s. A faster CPU just times out sooner.
KBC_POLLS_100MS      EQU 10600
KBC_TIMEOUT          EQU 1  ; 0.1 s: controller / keyboard replies
KBC_SELFTEST_TIMEOUT EQU 10 ; 1 s: the input adapter answers once its
                            ; keyboard detection is done (at most 1 s)

; -----------------------------------------------------------------------
; init_keyboard: returns AL=1 when a keyboard is present
; -----------------------------------------------------------------------
init_keyboard:
    push ds
    push es
    mov ax, 0x40
    mov ds, ax
    cli

    mov ax, BDA_BUF
    mov [BDA_BUF_START], ax
    mov [BDA_BUF_HEAD], ax
    mov [BDA_BUF_TAIL], ax
    add ax, 32
    mov [BDA_BUF_END], ax
    xor ax, ax
    mov [BDA_KB_FLAG], ax           ; also BDA_KB_FLAG_1
    mov [BDA_ALT_INPUT], al
    mov [BDA_KB_FLAG_3], al
    mov [BIOS_DATA_AREA_USE_KEYBOARD], al
    mov byte [BDA_KB_FLAG_2], KB2_LEDS ; unknown: forces sending LEDs off

%ifdef PS2_KEYBOARD
    ; discard anything left in the output buffer
    mov cx, 16
.flush:
    in al, 0x64
    test al, 1
    jz .flushed
    in al, 0x60
    loop .flush
.flushed:

    mov al, 0xAA                    ; controller self test
    call kbc_command
    mov dl, KBC_SELFTEST_TIMEOUT
    call kbc_read_n
    jc .no_keyboard
    cmp al, 0x55
    jne .no_keyboard

    ; Enable Set 2 -> Set 1 translation, keyboard interface and IRQ1
    mov al, 0x20                    ; read controller config byte
    call kbc_command
    call kbc_read
    jc .no_keyboard
    or al, 0x41                     ; bit 6 = translation, bit 0 = IRQ1
    and al, 0xEF                    ; bit 4 = 0: keyboard enabled
    push ax
    mov al, 0x60                    ; write controller config byte
    call kbc_command
    pop ax
    call kbc_write_data

    mov byte [BIOS_DATA_AREA_USE_KEYBOARD], 1
    call kb_update_leds

    xor ax, ax                      ; IRQ1 -> INT 9
    mov es, ax
    mov word [es:0x24], int9_handler
    mov [es:0x26], cs

    mov al, 1
    jmp .done
%endif

.no_keyboard:
    xor al, al
.done:
    sti
    pop es
    pop ds
    ret

; -----------------------------------------------------------------------
; 8042 controller helpers. Each wait gives up after a timeout.
; -----------------------------------------------------------------------

; AL = command for port 64h
kbc_command:
    push ax
    call kbc_wait_input
    pop ax
    out 0x64, al
    ret

; AL = byte for port 60h
kbc_write_data:
    push ax
    call kbc_wait_input
    pop ax
    out 0x60, al
    ret

kbc_wait_input:
    push cx
    mov cx, KBC_POLLS_100MS
.wait:
    in al, 0x64
    test al, 2
    loopnz .wait
    pop cx
    ret

; Waits for a byte in the output buffer: AL = byte, AH = status.
; CF = 1 on timeout. kbc_read_n: DL = timeout in 0.1 s units.
kbc_read:
    mov dl, KBC_TIMEOUT
kbc_read_n:
    push cx
.outer:
    mov cx, KBC_POLLS_100MS
.wait:
    in al, 0x64
    test al, 1
    jnz .ready
    loop .wait
    dec dl
    jnz .outer
    pop cx
    stc
    ret
.ready:
    mov ah, al
    in al, 0x60
    pop cx
    clc
    ret

; AL = byte to send to the keyboard; waits for its ack (FAh).
; Bytes arriving before the ack are keys: they are processed.
; CF = 1 on failure. DS = 40h, interrupts off.
kb_send:
    call kbc_write_data
.wait:
    call kbc_read
    jc .ret
    test ah, 0x20                   ; mouse byte: drop it
    jnz .wait
    cmp al, 0xFA
    je .ret                         ; CF = 0
    cmp al, 0xFE                    ; resend: give up
    stc
    je .ret
    call kb_process
    jmp .wait
.ret:
    ret

; Sends the lock state to the LEDs when it differs from what was sent.
; DS = 40h, interrupts off.
kb_update_leds:
    test byte [BDA_KB_FLAG_2], KB2_BUSY
    jnz .ret
    mov al, [BDA_KB_FLAG]
    mov cl, 4
    shr al, cl
    and al, KB2_LEDS                ; scroll = bit 0, num = 1, caps = 2
    mov ah, [BDA_KB_FLAG_2]
    and ah, KB2_LEDS
    cmp al, ah
    je .ret
    or byte [BDA_KB_FLAG_2], KB2_BUSY
    push ax
    mov al, 0xED
    call kb_send
    pop ax
    jc .sent                        ; no ack: don't retry until it changes
    push ax
    call kb_send
    pop ax
.sent:
    and byte [BDA_KB_FLAG_2], ~(KB2_LEDS | KB2_BUSY) & 0xFF
    or [BDA_KB_FLAG_2], al
.ret:
    ret

; -----------------------------------------------------------------------
; kb_service: processes every keyboard byte waiting in the controller.
; Shared by INT 9 and INT 16h. DS = 40h, interrupts off.
; -----------------------------------------------------------------------
kb_service:
    in al, 0x64
    test al, 1
    jz .done
    test al, 0x20                   ; mouse byte: leave it to the mouse
    jnz .done
    in al, 0x60
    mov ah, 0x4F                    ; INT 15h keyboard intercept
    stc
    int 0x15
    jnc kb_service                  ; key consumed
    call kb_process
    jmp kb_service
.done:
    jmp kb_update_leds

; Pause: wait for the next key (serviced by INT 9 or by polling here).
; No HLT: this must also work when no interrupt ever arrives.
kb_pause_wait:
.wait:
    sti
    nop
    cli
    call kb_service
    test byte [BDA_KB_FLAG_1], KB1_PAUSE
    jnz .wait
    ret

; -----------------------------------------------------------------------
; INT 9 (IRQ1)
; -----------------------------------------------------------------------
int9_handler:
    push ax
    push bx
    push cx
    push dx
    push si
    push ds
    mov ax, 0x40
    mov ds, ax

    call kb_service

    mov al, 0x20                    ; EOI
    out 0x20, al

    test byte [BDA_KB_FLAG_1], KB1_PAUSE
    jz .ret
    call kb_pause_wait
.ret:
    pop ds
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

; -----------------------------------------------------------------------
; kb_process: one Set 1 byte in AL. DS = 40h.
; Updates shift/lock state and stores keys (AH = scan, AL = ASCII).
; -----------------------------------------------------------------------
kb_process:
    mov ah, [BDA_KB_FLAG_3]
    cmp al, 0xE0
    je .set_e0
    cmp al, 0xE1
    je .set_e1
    test ah, KB3_E1                 ; Pause: E1 1D 45 / E1 9D C5
    jz .no_e1
    mov dl, al
    and dl, 0x7F
    cmp dl, 0x1D
    je .ret                         ; keep waiting for the 45
    and byte [BDA_KB_FLAG_3], ~KB3_E1 & 0xFF
    cmp al, 0x45
    je .pause
    ret

.set_e0:
    or byte [BDA_KB_FLAG_3], KB3_E0
    ret
.set_e1:
    or byte [BDA_KB_FLAG_3], KB3_E1
    ret

.no_e1:
    and byte [BDA_KB_FLAG_3], ~KB3_E0 & 0xFF ; a prefix covers one byte
    and ah, KB3_E0
    mov dh, ah                      ; DH != 0: E0 key
    mov dl, al                      ; DL bit 7: release
    and al, 0x7F
    jz .ret                         ; 00 / 80: overrun
    cmp dl, 0xFA
    jae .ret                        ; FA, FE, FF: replies / overrun

    ; --- shift keys (E0 2A / E0 36 are fake shifts: ignored) ---
    mov bl, KB_LSHIFT
    cmp al, 0x2A
    je .shift
    mov bl, KB_RSHIFT
    cmp al, 0x36
    jne .not_shift
.shift:
    test dh, dh
    jnz .ret
    jmp .set_or_clear_17

.not_shift:
    ; --- Ctrl / Alt: left in 18h, right in 96h, combined in 17h ---
    mov bl, KB1_LCTRL
    mov bh, KB3_RCTRL
    cmp al, 0x1D
    je .ctrl_alt
    mov bl, KB1_LALT
    mov bh, KB3_RALT
    cmp al, 0x38
    jne .not_ctrl_alt
.ctrl_alt:
    mov si, BDA_KB_FLAG_1
    test dh, dh
    jz .ca_side
    mov si, BDA_KB_FLAG_3
    mov bl, bh
.ca_side:
    test dl, 0x80
    jnz .ca_release
    or [si], bl
    jmp .ca_combine
.ca_release:
    not bl
    and [si], bl
.ca_combine:
    mov bl, [BDA_KB_FLAG_1]         ; LCTRL/LALT are bits 0/1,
    and bl, KB1_LCTRL | KB1_LALT
    mov bh, [BDA_KB_FLAG_3]         ; RCTRL/RALT are bits 2/3
    shr bh, 1
    shr bh, 1
    or bl, bh
    and bl, KB1_LCTRL | KB1_LALT
    shl bl, 1
    shl bl, 1                       ; -> KB_CTRL / KB_ALT
    mov bh, [BDA_KB_FLAG]
    test bh, KB_ALT
    jz .ca_store
    test bl, KB_ALT
    jnz .ca_store
    ; Alt released: emit an Alt + keypad number
    mov al, [BDA_ALT_INPUT]
    mov byte [BDA_ALT_INPUT], 0
    test al, al
    jz .ca_store
    push bx
    xor ah, ah
    call kb_store
    pop bx
.ca_store:
    and byte [BDA_KB_FLAG], ~(KB_CTRL | KB_ALT) & 0xFF
    or [BDA_KB_FLAG], bl
    ret

.not_ctrl_alt:
    ; --- lock keys (bit is the same in 17h and 18h) ---
    test dh, dh
    jnz .not_lock
    mov bl, KB_CAPS
    cmp al, 0x3A
    je .lock
    mov bl, KB_NUM
    cmp al, 0x45
    je .lock
    mov bl, KB_SCROLL
    cmp al, 0x46
    jne .not_lock
.lock:
    test dl, 0x80
    jnz .clear_held
    test byte [BDA_KB_FLAG], KB_CTRL
    jz .lock_toggle
    cmp al, 0x45                    ; Ctrl + Num Lock = Pause
    je .pause
    cmp al, 0x46                    ; Ctrl + Scroll Lock = Break
    je .break
.lock_toggle:
    test [BDA_KB_FLAG_1], bl
    jnz .ret                        ; held: auto repeat
    or [BDA_KB_FLAG_1], bl
    xor [BDA_KB_FLAG], bl
    ret

.not_lock:
    test dl, 0x80
    jz .make
    mov bl, KB_INS                  ; release: only Insert is tracked
    cmp al, 0x52
    jne .ret
.clear_held:
    not bl
    and [BDA_KB_FLAG_1], bl
.ret:
    ret

.set_or_clear_17:
    test dl, 0x80
    jnz .clear_17
    or [BDA_KB_FLAG], bl
    ret
.clear_17:
    not bl
    and [BDA_KB_FLAG], bl
    ret

.pause:
    xor byte [BDA_KB_FLAG_1], KB1_PAUSE
    ret

.break:
    mov ax, [BDA_BUF_START]         ; flush the buffer
    mov [BDA_BUF_HEAD], ax
    mov [BDA_BUF_TAIL], ax
    or byte [BDA_BIOS_BREAK], 0x80
    int 0x1B
    xor ax, ax
    jmp kb_store

.make:
    ; --- key press ---
    test byte [BDA_KB_FLAG_1], KB1_PAUSE
    jz .not_paused
    and byte [BDA_KB_FLAG_1], ~KB1_PAUSE & 0xFF ; any key ends the pause
    ret
.not_paused:
    mov bl, [BDA_KB_FLAG]
    cmp al, 0x53                    ; Ctrl + Alt + Del
    jne .not_cad
    mov bh, bl
    and bh, KB_CTRL | KB_ALT
    cmp bh, KB_CTRL | KB_ALT
    jne .not_cad
    mov word [BDA_RESET_FLAG], 0x1234 ; warm boot
    jmp 0xFFFF:0x0000
.not_cad:
    test dh, dh
    jz .not_grey
    ; --- E0 keys ---
    cmp al, 0x1C                    ; keypad Enter: same as Enter
    je .not_grey
    cmp al, 0x37                    ; Print Screen
    jne .not_prtsc
    test bl, KB_ALT                 ; Alt + PrtSc = SysRq: ignored
    jnz .ret
    int 0x05
    ret
.not_prtsc:
    cmp al, 0x46                    ; Ctrl + Pause = Break
    je .break
    cmp al, 0x35                    ; keypad /
    jne .grey_cursor
    test bl, KB_CTRL | KB_ALT
    jnz .ret
    mov ax, 0x352F
    jmp kb_store
.grey_cursor:
    cmp al, 0x47
    jb .ret
    cmp al, 0x53
    ja .ret
    test bl, KB_ALT
    jnz .ret
    test bl, KB_CTRL
    jnz .ctrl_cursor
    jmp .cursor

.not_grey:
    cmp al, 0x58
    ja .ret
    test bl, KB_ALT
    jz .not_alt

    ; --- Alt ---
    call .keypad_char               ; Alt + keypad digits: number entry
    jc .alt_not_keypad
    sub ah, '0'
    cmp ah, 9
    ja .ret
    mov dl, ah
    mov al, [BDA_ALT_INPUT]
    mov cl, 10
    mul cl
    add al, dl
    mov [BDA_ALT_INPUT], al
    ret
.alt_not_keypad:
    cmp al, 0x39                    ; Alt + Space
    jne .alt_not_space
    mov ax, 0x3920
    jmp kb_store
.alt_not_space:
    mov cx, 0x342D                  ; F1..F10: 68h..71h, F11/F12: 8Bh/8Ch
    call .fkey
    jnc .store_ah
    cmp al, 0x02
    jb .ret
    cmp al, 0x0D
    ja .alt_letter
    mov ah, al                      ; Alt + 1..= : 78h..83h
    add ah, 0x76
    jmp .store_ah
.alt_letter:
    call .letter                    ; Alt + letter: scan code only
    jc .ret
.store_scan:
    mov ah, al
.store_ah:
    xor al, al
    jmp kb_store

.not_alt:
    test bl, KB_CTRL
    jz .not_ctrl

    ; --- Ctrl ---
    mov cx, 0x3223                  ; F1..F10: 5Eh..67h, F11/F12: 89h/8Ah
    call .fkey
    jnc .store_ah
    cmp al, 0x47
    jb .ctrl_char
.ctrl_cursor:                       ; AL = 47h..53h, keypad or grey
    cmp al, 0x53
    ja .ret
    mov si, ax
    and si, 0xFF
    mov ah, [cs:ctrl_cursor_table - 0x47 + si]
    test ah, ah
    jz .ret
    jmp .store_ah
.ctrl_char:
    call .letter
    jc .ctrl_special
    mov ah, al
    mov al, [cs:scancode_table + si]
    sub al, 0x60                    ; Ctrl + letter: 01h..1Ah
    jmp kb_store
.ctrl_special:
    mov si, ctrl_special_table
.cs_next:
    mov ah, [cs:si]
    test ah, ah
    jz .ret
    cmp ah, al
    je .cs_found
    inc si
    inc si
    jmp .cs_next
.cs_found:
    mov al, [cs:si + 1]
    jmp kb_store

.not_ctrl:
    ; --- plain / Shift ---
    mov cx, 0x2E00                  ; F1..F10: 3Bh..44h, F11/F12: 85h/86h
    test bl, KB_LSHIFT | KB_RSHIFT
    jz .plain_f
    mov cx, 0x3019                  ; F1..F10: 54h..5Dh, F11/F12: 87h/88h
.plain_f:
    call .fkey
    jnc .store_ah
    cmp al, 0x47
    jb .char

    ; keypad
    call .keypad_char
    jc .ret
    cmp al, 0x4A                    ; keypad - and + always type
    je .store_ascii
    cmp al, 0x4E
    je .store_ascii
    mov bh, 0                       ; digits when Num Lock XOR Shift
    test bl, KB_LSHIFT | KB_RSHIFT
    jz .kp_shift
    inc bh
.kp_shift:
    test bl, KB_NUM
    jz .kp_num
    xor bh, 1
.kp_num:
    test bh, bh
    jz .cursor
.store_ascii:
    xchg al, ah                     ; AH = scan, AL = char
    jmp kb_store

.cursor:
    cmp al, 0x4C                    ; keypad 5 without Num Lock: nothing
    je .ret
    cmp al, 0x52                    ; Insert toggles insert mode
    jne .store_scan
    test byte [BDA_KB_FLAG_1], KB_INS
    jnz .store_scan                 ; held: don't toggle on repeat
    or byte [BDA_KB_FLAG_1], KB_INS
    xor byte [BDA_KB_FLAG], KB_INS
    jmp .store_scan

.char:
    cmp al, 0x39
    ja .ret
    cmp al, 0x0F                    ; Shift + Tab
    jne .not_backtab
    test bl, KB_LSHIFT | KB_RSHIFT
    jnz .store_scan
.not_backtab:
    test bl, KB_LSHIFT | KB_RSHIFT
    mov bl, 0                       ; BL = 1: shifted
    jz .char_shift
    inc bl
.char_shift:
    call .letter
    jc .no_caps
    test byte [BDA_KB_FLAG], KB_CAPS
    jz .no_caps
    xor bl, 1                       ; Caps Lock inverts Shift on letters
.no_caps:
    mov ah, al
    mov al, [cs:scancode_table + si]
    test bl, bl
    jz .got_char
    mov al, [cs:scancode_table_shifted + si]
.got_char:
    test al, al
    jz .ret
    jmp kb_store

; AL = scan. F1..F10 -> AH = scan + CL, F11/F12 -> AH = scan + CH.
; CF = 1 if not a function key.
.fkey:
    mov ah, al
    cmp al, 0x3B
    jb .not_f
    cmp al, 0x44
    ja .f11
    add ah, cl
    clc
    ret
.f11:
    cmp al, 0x57
    jb .not_f
    cmp al, 0x58
    ja .not_f
    add ah, ch
    clc
    ret
.not_f:
    stc
    ret

; AL = scan -> SI = scan; CF = 0 if the unshifted char is a letter
.letter:
    mov si, ax
    and si, 0xFF
    cmp al, 0x39
    ja .not_letter
    cmp byte [cs:scancode_table + si], 'a'
    jb .not_letter
    cmp byte [cs:scancode_table + si], 'z'
    ja .not_letter
    clc
    ret
.not_letter:
    stc
    ret

; AL = scan; keypad keys (47h..53h): AH = char, CF = 0
.keypad_char:
    cmp al, 0x47
    jb .not_kp
    cmp al, 0x53
    ja .not_kp
    mov si, ax
    and si, 0xFF
    mov ah, [cs:keypad_table - 0x47 + si]
    clc
    ret
.not_kp:
    stc
    ret

; AX = key; drops it when the buffer is full. DS = 40h.
kb_store:
    mov bx, [BDA_BUF_TAIL]
    mov si, bx
    inc si
    inc si
    cmp si, [BDA_BUF_END]
    jb .no_wrap
    mov si, [BDA_BUF_START]
.no_wrap:
    cmp si, [BDA_BUF_HEAD]
    je .full
    mov [bx], ax
    mov [BDA_BUF_TAIL], si
.full:
    ret

keypad_table        db "789-456+1230."
ctrl_cursor_table   db 0x77, 0, 0x84, 0, 0x73, 0, 0x74, 0, 0x75, 0, 0x76, 0, 0
; Ctrl + key -> ASCII for non-letters (scan, char), 0-terminated
ctrl_special_table  db 0x01, 0x1B, 0x03, 0x00, 0x07, 0x1E, 0x0C, 0x1F
                    db 0x0E, 0x7F, 0x1A, 0x1B, 0x1B, 0x1D, 0x1C, 0x0A
                    db 0x2B, 0x1C, 0x39, 0x20, 0

; -----------------------------------------------------------------------
; INT 16h
; -----------------------------------------------------------------------
int16_handler:
    push ds
    push bx
    push si
    mov bx, 0x40
    mov ds, bx

    test byte [BIOS_DATA_AREA_USE_KEYBOARD], 1
    jnz .use_keyboard

    cmp ah, 0x00
    je .read_serial
    cmp ah, 0x01
    je .peek_serial
    jmp .done
.read_serial:
    call serial_getc
    jmp .done
.peek_serial:
    call serial_peekc
    jmp .done

.use_keyboard:
    cmp ah, 0x00
    je .read
    cmp ah, 0x01
    je .peek
    cmp ah, 0x02
    je .status
    jmp .done

.read:                              ; blocking
    call .poll
    jne .take
    sti
    nop
    jmp .read
.take:
    mov ax, [bx]
    inc bx
    inc bx
    cmp bx, [BDA_BUF_END]
    jb .no_wrap
    mov bx, [BDA_BUF_START]
.no_wrap:
    mov [BDA_BUF_HEAD], bx
    sti
    jmp .done

.peek:                              ; ZF = 1: no key
    call .poll
    je .peek_done
    mov ax, [bx]
.peek_done:
    sti
    jmp .done

.status:
    mov al, [BDA_KB_FLAG]

.done:
    pop si
    pop bx
    pop ds
    sti
    retf 2 ; instead of iret to return flags

; Services the controller (same as INT 9), then BX = head; ZF = 1 if the
; buffer is empty. Returns with interrupts off.
.poll:
    push ax
    push cx
    push dx
    cli
    call kb_service
    test byte [BDA_KB_FLAG_1], KB1_PAUSE
    jz .not_paused
    call kb_pause_wait
.not_paused:
    pop dx
    pop cx
    pop ax
    mov bx, [BDA_BUF_HEAD]
    cmp bx, [BDA_BUF_TAIL]
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
