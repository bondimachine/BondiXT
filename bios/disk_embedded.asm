int13_handler:

    ; define disk geometry
    DISK_CYLINDERS      equ 40
    DISK_HEADS          equ 2
    DISK_SECTORS        equ 9
    DISK_SECTOR_SIZE    equ 512

    cmp     ah, 2
    je      .read_sectors

    cmp     ah, 6 ; 06h read with retry
    je      .read_sectors

    cmp     ah, 8 ; 08h read with retry
    je      .get_drive_parameters

    cmp     ah, 0x15 ; 08h get drive type 
    je      .get_floppy_type

    jmp     .ignore

.get_drive_parameters:
    ; DL = drive number
    ; Output:
    ; CF = 0 on success
    ; AH = 0
    ; DL = number of drives
    ; DH = max head number
    ; CH = max cylinder number
    ; CL = max sector number
    stc
    cmp dl, 0x0
    jne .done

    mov ax, 0
    mov dl, 1 ; number of drives
    mov dh, DISK_HEADS - 1
    mov ch, DISK_CYLINDERS - 1
    mov cl, DISK_SECTORS
    clc
    jmp .done

.read_sectors:
    ; AL = #sectors, CH = cylinder, CL = sector, DH = head, DL = drive, ES:BX = buffer
    stc
    cmp dl, 0
    jne .done ; for the moment we only support floppy

    push cx
    push ds
    push di
    push si

    push ax
    push cx

    mov ch, 0
.cont:
    mov ah, 0x0E 
    mov al, '.'
    int 10h
    dec cl
    jnz .cont

    ; Calculate LBA address
    ; LBA = (cylinder * number_of_heads + head) * sectors_per_track + (sector - 1)
    
    ; SI = cylinder * number_of_heads
    xor ax, ax
    mov al, ch ; cylinder
    mov cl, DISK_HEADS
    mul cl
    mov si, ax

    ; SI += head
    xor ch, ch ; clear high bits of cx
    mov cl, dh ; head
    add si, cx

    ; SI *= sectors_per_track
    mov ax, si
    mov cl, DISK_SECTORS
    mul cl
    mov si, ax

    ; SI += sector - 1
    pop cx ; CX was overwritten above, restored here. CL is the starting sector.
    and cl, 0x3F ; sector is in lower 6 bits
    xor ch, ch
    dec cx
    add si, cx

    ; SI is now LBA, calculate memory offset
    ; offset = LBA * 512
    mov ax, si
    mov cx, DISK_SECTOR_SIZE
    mul cx
    mov si, ax
    
    ; Source address in DS:SI. Disk image must start at DS:0
    mov ax, DISK_IMAGE_SEGMENT
    mov ds, ax
    and si, 0xFFFF

    ; Set byte count to copy in CX
    pop ax ; recover original read count
    mov cl, al
    xor ch, ch
    mov ax, DISK_SECTOR_SIZE
    mul cx
    mov cx, ax

    ; ES:DI is destination
    mov di, bx

    ; DS:SI is source
    rep movsb

    pop si
    pop di
    pop ds
    pop cx

    clc
    jmp .done

.get_floppy_type:
    clc
    mov ah, 1
    jmp .done

.ignore:
    mov ah, 0;
    clc ; just say we are ok!

.done:
    iret
