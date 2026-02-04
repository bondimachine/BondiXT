BITS 16

P0 EQU 0b01010101
P1 EQU 0b10101010

; %define QEMU

times 0xE000 - ($ - $$) db 0 ; put the code in the last 8kb

start:

    mov ax, 0
    mov ds, ax
    mov si, 0
    mov cl, 1

    mov dx, 0x378
    mov al, cl
    out dx, al

continue:
    mov al, P0
    mov [ds:si], al
    mov al, [ds:si]
    cmp al, P0
    jne error

    mov al, P1
    mov [ds:si], al
    mov al, [ds:si]
    cmp al, P1
    jne error

    inc si
    jnz continue
    inc cl
    cmp cl, 11
    je done
    mov ax, ds
    add ax, 0x1000
    mov ds, ax

    mov al, cl
%ifdef QEMU
    add al, '0'
%endif
    out dx, al

%ifdef QEMU
    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al
    mov dx, 0x378
%endif

    jmp continue

error:
    mov al, cl
%ifdef QEMU
    add al, 'A'
%else
    or al, 0x80
%endif
    out dx, al

%ifdef QEMU
    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al
    mov dx, 0x378
%endif

    hlt

done:
%ifdef QEMU
    mov al, 'S'
%else
    mov al, 0b11011011
%endif
    out dx, al

%ifdef QEMU
    mov dx, 0x37A
    mov al, 0x08 | 0x04 | 1 ; 0x08 = select, 0x04 = !initialize, 1 = strobe
    out dx, al
    mov al, 0x08 | 0x04
    out dx, al
    mov dx, 0x378
%endif

    hlt

reset_vector:
    times 0xFFF0 - ($ - $$) db 0
    jmp start

padding: ; 64kb
    times 0x10000 - ($ - $$) db 0