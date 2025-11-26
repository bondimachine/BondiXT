BITS 16

P0 EQU 0b01010101
P1 EQU 0b10101010

; %define QEMU

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

start:


; March C- algorithm {↑ (w0); ↑ (r0, w1); ↑ (r1, w0); ↓ (r0, w1); ↓ (r1, w0); ↓ (r0)}

    cli
    mov bp, 0
    mov es, bp
    mov ax, cs
    mov ds, ax

    mov dx, 0x378
    mov al, 0
    out dx, al

    mov al, 1
    mov si, _phase1
    jmp print_phase

_phase1:
    mov di, 0
    mov al, P0 
    mov cx, 0xFFFF
    rep stosb
    stosb

    mov ax, bp
    ; poormans "stack"
    mov si, _continue_phase1
    jmp print_nibble

_continue_phase1:
    inc bp
    cmp bp, 10
    je _done_phase1

    mov ax, bp
    rol ax, 12
    mov es, ax
    jmp _phase1

_done_phase1:


    mov al, 2
    mov si, _phase2
    jmp print_phase
    
_phase2:
; Phase 2: ↑ (r0, w1)

    mov bl, P0
    mov bh, P1

    mov sp, _done_phase2
    jmp march_up

_done_phase2:
    mov al, 3
    mov si, _phase3
    jmp print_phase
    
_phase3:
; Phase 3: ↑ (r1, w0)

    mov bl, P1
    mov bh, P0

    mov sp, _done_phase3
    jmp march_up

_done_phase3:

    mov al, 4
    mov si, _phase4
    jmp print_phase
    
_phase4:

; Phase 4: ↓ (r0, w1)
    mov bl, P0
    mov bh, P1

    mov sp, _done_phase4
    jmp march_down

_done_phase4:

    mov al, 5
    mov si, _phase5
    jmp print_phase
    
_phase5:
; Phase 5: ↓ (r1, w0)
    mov bl, P1
    mov bh, P0

    mov sp, _done_phase5
    jmp march_down

_done_phase5:

    mov al, 6
    mov si, _phase6
    jmp print_phase
    
_phase6:

; Phase 6: ↓ (r0) read-only verify zeros
    mov bl, P0
    mov bh, P0 ; we don't need to write, but it is easier to reuse march_down
    mov sp, success
    jmp march_down

success:
    ; all phases complete - success
    mov si, halt
    jmp print_success

march_up:
    mov bp, 0
    mov es, bp

.outer_loop:

    mov di, 0
    mov cx, 0

.inner_loop:
    mov al, [es:di]
    cmp al, bl
    jne error
    mov [es:di], bh
    inc di
    dec cx
    jnz .inner_loop

    mov ax, bp
    mov si, .continue
    jmp print_nibble

.continue:

    inc bp
    cmp bp, 10
    je .done

    mov ax, bp
    rol ax, 12
    mov es, ax
    jmp .outer_loop

.done:
    mov si, sp
    jmp si


march_down:
    mov bp, 9
    mov ax, bp
    rol ax, 12
    mov es, ax

.outer_loop:

    mov di, 0xFFFF
    mov cx, 0

.inner_loop:
    mov al, [es:di]
    cmp al, bl
    jne error
    mov [es:di], bh
    dec di
    dec cx
    jnz .inner_loop

    mov ax, bp
    mov si, .continue
    jmp print_nibble

.continue:

    cmp bp, 0
    je .done
    dec bp

    mov ax, bp
    rol ax, 12
    mov es, ax
    jmp .outer_loop

.done:
    mov si, sp
    jmp si

%ifdef QEMU
; prints lower 4 bits of al
print_nibble_error:
print_nibble:
    and al, 0x0F
    cmp al, 10
    jl .not_bigger
    add al, 'A' - 10 - '0'
.not_bigger:
    add al, '0'
    jmp print

print_blink0:
    mov al, '_'
    jmp print

print_blink1:
    mov al, '|'
    jmp print

print_error:
    mov al, 'E'
    jmp print

print_success:
    mov al, 'S'
    jmp print
%else 

print_nibble_error:
    or al, 0x40
print_nibble:
    jmp print

print_blink0:
    mov al, P0
    jmp print

print_blink1:
    mov al, P1
    jmp print

print_error:
    mov al, 0x40
    jmp print

print_success:
    mov al, 0b11000011
    jmp print

%endif


; destroys si, dx, al
print:
    mov dx, 0x378
    out dx, al

%ifdef QEMU
    ; this is only needed for QEMU to print on the screen
    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al

    mov al, 13
    mov dx, 0x378
    out dx, al

    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al


    mov al, 10
    mov dx, 0x378
    out dx, al

    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al
%endif

    jmp si

; prints al (as a character) to parallel port 0x378 with wait/blink
; destroys si, dx, cx, sp, al
print_phase:
    mov sp, si
%ifndef QEMU
    sub al, 1
    mov cl, al
    mov al, 1
    rol al, cl
    or al, 0x80
%endif
    mov bl, al
    mov si, .blink0
    jmp print_blink0
.blink0:
    mov si, .wait0
    jmp _wait
.wait0:
    mov si, .blink0_1
    jmp print_blink1
.blink0_1:
    mov si, .wait0_1
    jmp _wait
.wait0_1:
    mov al, bl
    mov si, .blink1
    jmp print_nibble
.blink1:
    mov si, .wait1
    jmp _wait
.wait1:    
    mov si, .blink2
    jmp print_blink1
.blink2:
    mov si, .wait2
    jmp _wait
.wait2:
    mov al, bl
    mov si, .blink3
    jmp print_nibble
.blink3:    
    mov si, .wait3
    jmp _wait
.wait3:    
    mov si, .blink4
    jmp print_blink0
.blink4:
    mov si, .wait4
    jmp _wait
.wait4:
    mov si, sp
    jmp si


_wait:
    mov cx, 0xFFFF
.loop:    
    dec cx
    jnz .loop

    jmp si

error:
    ; error - print 'E' and halt
    mov si, .blink1
    jmp print_error
.blink1:
    mov si, .wait1
    jmp _wait
.wait1:
    ; es:di failing address
    mov ax, es
    ror ax, 11
    mov si, .blink2
    jmp print_nibble_error
.blink2:
    mov si, .wait2
    jmp _wait
.wait2:
    ; es:di failing address
    mov ax, di
    mov al, ah
    ror al, 4
    mov si, .blink3
    jmp print_nibble_error
.blink3:
    mov si, .wait3
    jmp _wait
.wait3:
    ; es:di failing address
    mov ax, di
    mov al, ah
    mov si, .blink4
    jmp print_nibble_error
.blink4:
    mov si, .wait4
    jmp _wait
.wait4:
    ; es:di failing address
    mov ax, di
    ror al, 4
    mov si, .blink5
    jmp print_nibble_error
.blink5:
    mov si, .wait5
    jmp _wait
.wait5:
    ; es:di failing address
    mov ax, di
    and al, 0x0F
    mov si, .blink6
    jmp print_nibble_error
.blink6:
    mov si, .wait6
    jmp _wait
.wait6:
    mov al, [es:di]
    ror al, 4
    mov si, .blink7
    jmp print_nibble_error
.blink7:
    mov si, .wait7
    jmp _wait
.wait7:
    mov al, [es:di]
    and al, 0x0F
    mov si, halt
    jmp print_nibble_error

halt:    
    hlt

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0