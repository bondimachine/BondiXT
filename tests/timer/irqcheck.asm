; irqcheck.com - checks that the BIOS keeps the timer interrupt alive.
;
; 1. Calls each BIOS service with interrupts enabled and checks that IF is
;    still set on return (catches handlers that return via "retf 2" without
;    an sti).
; 2. Hammers BIOS services in a loop without re-enabling interrupts ourselves
;    and checks that the BDA tick count keeps pace with the PIT. The PIT is
;    polled directly as an independent clock: in mode 3 its latched count
;    wraps twice per IRQ0 period, so ticks should be ~= wraps / 2.
; 3. Checks the PIC is clean afterwards (nothing left in service, IRQ0 not
;    masked).
; 4. Calls INT 16h AH=00 (blocking) and checks IF on return.
;
; Whenever something fails it dumps IF, the PIC IMR/IRR/ISR, two PIT count
; readings, the BDA tick count and the INT 08h vector, which tells apart:
;   IF=0                      -> a handler left interrupts disabled
;   IMR bit 0 set             -> IRQ0 masked
;   ISR bit 0 stuck           -> missing EOI
;   IRR bit 0 set with IF=1   -> CPU not acknowledging (INTA / bus problem)
;   PIT count not changing    -> PIT not counting (clock / gate)
;
; Exit code (ERRORLEVEL) = number of failed checks.

CPU 8086
bits 16
org 0x100

TICKS_TARGET    equ 54      ; ~3 s at 18.2 Hz
STALL_WRAPS     equ 16      ; ~8 IRQ0 periods without a tick = stalled

start:
    sti
    cld
    mov si, title_msg
    call print_string

; ---------------------------------------------------------------------------
; 1. IF preserved across BIOS calls
; ---------------------------------------------------------------------------
    mov si, part1_msg
    call print_string

    mov word [table_ptr], if_tests
.next_test:
    mov bx, [table_ptr]
    mov si, [bx]
    cmp si, 0
    je .tests_done
    mov di, [bx+2]
    add word [table_ptr], 4
    call run_if_test
    jmp .next_test
.tests_done:

; ---------------------------------------------------------------------------
; 2. Ticks keep pace with the PIT while BIOS services are called
; ---------------------------------------------------------------------------
    mov si, part2_msg
    call print_string

    mov si, load_disk_msg
    mov di, work_disk
    call load_test

    mov si, load_mixed_msg
    mov di, work_mixed
    call load_test

; ---------------------------------------------------------------------------
; 3. PIC state is clean
; ---------------------------------------------------------------------------
    mov si, part3_msg
    call print_string

    call read_isr
    mov si, isr_msg
    call print_string
    push ax
    call print_hex8
    pop ax
    cmp al, 0
    jne .pic_fail
    in al, 0x21
    mov [imr_val], al
    mov si, imr_msg
    call print_string
    call print_hex8
    test byte [imr_val], 1
    jnz .pic_fail
    call print_pass
    jmp .pic_done
.pic_fail:
    call print_fail
    call dump_state
.pic_done:

; ---------------------------------------------------------------------------
; 4. Blocking keyboard read
; ---------------------------------------------------------------------------
    mov si, part4_msg
    call print_string
    mov si, name_int16_00
    mov di, t_int16_00
    call run_if_test

; ---------------------------------------------------------------------------
    mov si, summary_msg
    call print_string
    mov ax, [failures]
    call print_hex16
    call print_crlf

    mov al, [failures]
    mov ah, 0x4C
    int 0x21

; ---------------------------------------------------------------------------
; run_if_test: SI = name, DI = routine that issues the BIOS call.
; Calls it with IF=1 and checks IF on return.
; ---------------------------------------------------------------------------
run_if_test:
    push si
    call print_string
    push ds
    push es
    push bp
    sti
    call di
    pushf
    pop ax
    mov [cs:result_flags], ax
    pop bp
    pop es
    pop ds
    sti                         ; keep going even if the call left IF=0
    pop si
    test word [result_flags], 0x200
    jz .fail
    call print_pass
    ret
.fail:
    call print_fail
    mov si, if_cleared_msg
    call print_string
    ret

; ---------------------------------------------------------------------------
; BIOS calls under test
; ---------------------------------------------------------------------------
t_int13_02:                     ; read boot sector of drive 0
    push cs
    pop es
    mov bx, sector_buf
    mov ax, 0x0201
    mov cx, 0x0001
    mov dx, 0x0000
    int 0x13
    ret
t_int13_08:
    mov ah, 0x08
    mov dl, 0x00
    int 0x13
    ret
t_int13_15:
    mov ah, 0x15
    mov dl, 0x00
    int 0x13
    ret
t_int13_bad:
    mov ah, 0x55
    mov dl, 0x00
    int 0x13
    ret
t_int16_01:
    mov ah, 0x01
    int 0x16
    ret
t_int16_02:
    mov ah, 0x02
    int 0x16
    ret
t_int16_11:                     ; extended peek (non-blocking)
    mov ah, 0x11
    int 0x16
    ret
t_int16_bad:
    mov ah, 0x55
    int 0x16
    ret
t_int16_00:
    mov si, press_key_msg
    call print_string
    mov ah, 0x00
    int 0x16
    ret
t_int10_0f:
    mov ah, 0x0F
    int 0x10
    ret
t_int10_0e:
    mov ax, 0x0E2E              ; print '.'
    mov bx, 0x0007
    int 0x10
    ret
t_int11:
    int 0x11
    ret
t_int12:
    int 0x12
    ret
t_int14_03:
    mov ah, 0x03
    mov dx, 0x0000
    int 0x14
    ret
t_int15_bad:
    mov ah, 0x88
    int 0x15
    ret
t_int1a_00:
    mov ah, 0x00
    int 0x1A
    ret

; Work done on each iteration of the load test. No sti of our own: if a
; handler leaves IF=0, it stays 0 and the stall shows up.
work_disk:
    push es
    call t_int13_02
    pop es
    ret
work_mixed:
    push es
    call t_int16_01
    call t_int10_0f
    call t_int13_02
    pop es
    ret

; ---------------------------------------------------------------------------
; load_test: SI = name, DI = work routine
; ---------------------------------------------------------------------------
load_test:
    call print_string
    mov [work_ptr], di
    sti
    call read_ticks
    mov [start_ticks], ax
    call read_pit
    mov [last_pit], ax
    mov word [wraps], 0
    mov word [iterations], 0

.loop:
    call word [work_ptr]

    call read_pit
    cmp ax, [last_pit]
    mov [last_pit], ax
    jbe .no_wrap
    inc word [wraps]
.no_wrap:
    call read_ticks
    sub ax, [start_ticks]
    mov [delta_ticks], ax
    cmp ax, TICKS_TARGET
    jae .finished

    cmp ax, 0
    jne .not_stalled
    cmp word [wraps], STALL_WRAPS
    jae .stalled
.not_stalled:
    ; ticks too slow compared with the PIT: give up and report the ratio
    cmp word [wraps], TICKS_TARGET * 4
    jae .finished
    inc word [iterations]
    jnz .loop
    ; 65536 iterations with no target reached
    cmp word [wraps], 0
    jne .finished
    mov si, pit_dead_msg
    jmp .report_fail

.stalled:
    mov si, stalled_msg
.report_fail:
    call print_fail
    call print_string
    call dump_state
    cmp word [wraps], 0         ; PIT not running: nothing to time the retry with
    je .no_recover
    sti                         ; does it recover once interrupts are on?
    call read_ticks
    mov [start_ticks], ax
    mov word [wraps], 0
.recover:
    call read_pit
    cmp ax, [last_pit]
    mov [last_pit], ax
    jbe .recover
    inc word [wraps]
    cmp word [wraps], 8
    jb .recover
    call read_ticks
    cmp ax, [start_ticks]
    mov si, recovered_msg
    jne .print_recover
    mov si, not_recovered_msg
.print_recover:
    call print_string
.no_recover:
    sti
    ret

.finished:
    sti
    mov si, ticks_msg
    call print_string
    mov ax, [delta_ticks]
    call print_hex16
    mov si, wraps_msg
    call print_string
    mov ax, [wraps]
    call print_hex16
    mov si, iter_msg
    call print_string
    mov ax, [iterations]
    call print_hex16
    ; pass if ticks*2 + ticks/4 + 4 >= wraps (allows ~12% slack)
    mov ax, [delta_ticks]
    mov bx, ax
    shl ax, 1
    mov cl, 2
    shr bx, cl
    add ax, bx
    add ax, 4
    cmp ax, [wraps]
    jb .lost
    call print_pass
    ret
.lost:
    call print_fail
    mov si, lost_msg
    call print_string
    call dump_state
    ret

; ---------------------------------------------------------------------------
; Hardware helpers (do not change IF)
; ---------------------------------------------------------------------------
read_ticks:                     ; AX = BDA tick count, low word
    push es
    mov ax, 0x40
    mov es, ax
    mov ax, [es:0x6C]
    pop es
    ret

read_pit:                       ; AX = latched PIT channel 0 count
    pushf
    cli
    mov al, 0x00                ; latch channel 0
    out 0x43, al
    in al, 0x40
    mov ah, al
    in al, 0x40
    xchg al, ah
    popf
    ret

read_irr:                       ; AL = PIC IRR
    mov al, 0x0A
    out 0x20, al
    in al, 0x20
    ret

read_isr:                       ; AL = PIC ISR
    mov al, 0x0B
    out 0x20, al
    in al, 0x20
    push ax
    mov al, 0x0A                ; back to IRR, the power-on default
    out 0x20, al
    pop ax
    ret

; Prints IF, IMR, IRR, ISR, PIT x2, ticks, INT 08h vector. Preserves IF.
dump_state:
    pushf
    pop ax
    mov [dump_flags], ax
    mov si, dump_if_msg
    call print_string
    mov al, '0'
    test word [dump_flags], 0x200
    jz .if0
    mov al, '1'
.if0:
    call print_char

    in al, 0x21
    mov [imr_val], al
    mov si, dump_imr_msg
    call print_string
    mov al, [imr_val]
    call print_hex8

    call read_irr
    mov [imr_val], al
    mov si, dump_irr_msg
    call print_string
    mov al, [imr_val]
    call print_hex8

    call read_isr
    mov [imr_val], al
    mov si, dump_isr_msg
    call print_string
    mov al, [imr_val]
    call print_hex8

    mov si, dump_pit_msg
    call print_string
    call read_pit
    call print_hex16
    mov al, ','
    call print_char
    call read_pit
    call print_hex16

    mov si, dump_ticks_msg
    call print_string
    call read_ticks
    call print_hex16

    mov si, dump_vec_msg
    call print_string
    push es
    xor ax, ax
    mov es, ax
    mov ax, [es:0x22]
    call print_hex16
    mov al, ':'
    call print_char
    mov ax, [es:0x20]
    call print_hex16
    pop es
    call print_crlf
    ret

; ---------------------------------------------------------------------------
; Output (INT 10h teletype; iret restores the caller's IF)
; ---------------------------------------------------------------------------
print_pass:
    push si
    mov si, pass_msg
    call print_string
    pop si
    ret

print_fail:
    push si
    inc word [cs:failures]
    mov si, fail_msg
    call print_string
    pop si
    ret

print_string:
    push ax
    push bx
    push si
.next:
    lodsb
    cmp al, 0
    je .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .next
.done:
    pop si
    pop bx
    pop ax
    ret

print_char:
    push ax
    push bx
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    pop bx
    pop ax
    ret

print_crlf:
    push ax
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    pop ax
    ret

print_hex16:                    ; AX
    push ax
    mov al, ah
    call print_hex8
    pop ax
    push ax
    call print_hex8
    pop ax
    ret

print_hex8:                     ; AL
    push ax
    push cx
    mov ah, al
    mov cl, 4
    shr al, cl
    call .nibble
    mov al, ah
    and al, 0x0F
    call .nibble
    pop cx
    pop ax
    ret
.nibble:
    add al, '0'
    cmp al, '9'
    jbe .out
    add al, 'A' - '9' - 1
.out:
    jmp print_char

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
if_tests:
    dw name_int13_02, t_int13_02
    dw name_int13_08, t_int13_08
    dw name_int13_15, t_int13_15
    dw name_int13_bad, t_int13_bad
    dw name_int16_01, t_int16_01
    dw name_int16_02, t_int16_02
    dw name_int16_11, t_int16_11
    dw name_int16_bad, t_int16_bad
    dw name_int10_0f, t_int10_0f
    dw name_int10_0e, t_int10_0e
    dw name_int11, t_int11
    dw name_int12, t_int12
    dw name_int14_03, t_int14_03
    dw name_int15_bad, t_int15_bad
    dw name_int1a_00, t_int1a_00
    dw 0

title_msg       db "BondiXT IRQ0 / IF check", 13, 10, 0
part1_msg       db 13, 10, "1. IF preserved across BIOS calls", 13, 10, 0
part2_msg       db 13, 10, "2. Ticks vs PIT under BIOS load", 13, 10, 0
part3_msg       db 13, 10, "3. PIC state", 13, 10, 0
part4_msg       db 13, 10, "4. Blocking keyboard read", 13, 10, 0
summary_msg     db 13, 10, "Failures: ", 0

name_int13_02   db "  INT 13h AH=02 read    ", 0
name_int13_08   db "  INT 13h AH=08 params  ", 0
name_int13_15   db "  INT 13h AH=15 type    ", 0
name_int13_bad  db "  INT 13h AH=55 unknown ", 0
name_int16_01   db "  INT 16h AH=01 peek    ", 0
name_int16_02   db "  INT 16h AH=02 shift   ", 0
name_int16_11   db "  INT 16h AH=11 ext peek", 0
name_int16_bad  db "  INT 16h AH=55 unknown ", 0
name_int16_00   db "  INT 16h AH=00 read    ", 0
name_int10_0f   db "  INT 10h AH=0F mode    ", 0
name_int10_0e   db "  INT 10h AH=0E tty     ", 0
name_int11      db "  INT 11h equipment     ", 0
name_int12      db "  INT 12h memory        ", 0
name_int14_03   db "  INT 14h AH=03 status  ", 0
name_int15_bad  db "  INT 15h AH=88 unknown ", 0
name_int1a_00   db "  INT 1Ah AH=00 ticks   ", 0

load_disk_msg   db "  INT 13h reads    ", 0
load_mixed_msg  db "  13h+16h+10h mix  ", 0
ticks_msg       db " ticks=", 0
wraps_msg       db " pit/2=", 0
iter_msg        db " iter=", 0
isr_msg         db "  ISR=", 0
imr_msg         db " IMR=", 0
press_key_msg   db "(press a key) ", 0

pass_msg        db " PASS", 13, 10, 0
fail_msg        db " FAIL", 13, 10, 0
if_cleared_msg  db "    returned with IF=0 (interrupts left disabled)", 13, 10, 0
stalled_msg     db "    ticks stopped while the PIT keeps running", 13, 10, 0
pit_dead_msg    db "    no ticks and the PIT count never wrapped", 13, 10, 0
lost_msg        db "    ticks fall behind the PIT (IRQ0s lost)", 13, 10, 0
recovered_msg   db "    ticks resume after STI -> a handler left IF=0", 13, 10, 0
not_recovered_msg db "    ticks still stopped after STI -> PIC/PIT/IRQ0 path", 13, 10, 0

dump_if_msg     db "    IF=", 0
dump_imr_msg    db " IMR=", 0
dump_irr_msg    db " IRR=", 0
dump_isr_msg    db " ISR=", 0
dump_pit_msg    db " PIT=", 0
dump_ticks_msg  db " TICKS=", 0
dump_vec_msg    db " INT08=", 0

failures        dw 0
table_ptr       dw 0
work_ptr        dw 0
result_flags    dw 0
dump_flags      dw 0
imr_val         db 0
start_ticks     dw 0
delta_ticks     dw 0
last_pit        dw 0
wraps           dw 0
iterations      dw 0

sector_buf:     ; 512 bytes past the end of the program (inside the 64K .com segment)
