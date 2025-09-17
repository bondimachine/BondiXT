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

    cmp     ah, 8
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

    clc
    cmp dl, 0x0
    jne .drive_not_found

    mov ax, 0
    mov dl, 1 ; number of drives
    mov dh, DISK_HEADS - 1
    mov ch, DISK_CYLINDERS - 1
    mov cl, DISK_SECTORS
    jmp .done

.drive_not_found:
    mov dl, 0
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
    
%ifdef DEBUG_DISK
    ; Print C-H-S 
    mov al, ch 
    call serial_print_hex

    mov al, '-'
    call serial_putc

    mov al, dh
    call serial_print_hex

    mov al, '-'
    call serial_putc

    mov al, cl
    call serial_print_hex

    mov al, ' '
    call serial_putc
%endif 

    ; Calculate LBA address
    ; LBA = (cylinder * number_of_heads + head) * sectors_per_track + (sector - 1)
    
    ; AX = cylinder * number_of_heads
    xor ax, ax
    mov al, ch ; cylinder
    mov cl, DISK_HEADS
    mul cl
    mov si, ax

    ; AX += head
    xor ch, ch ; clear high bits of cx
    mov cl, dh ; head
    add ax, cx

    ; AX *= sectors_per_track
    mov cl, DISK_SECTORS
    mul cl

    ; SI += sector - 1
    pop cx ; CX was overwritten above, restored here. CL is the starting sector.
    and cl, 0x3F ; sector is in lower 6 bits
    xor ch, ch
    dec cx
    add ax, cx

    ; AX is now LBA, calculate memory segment
    ; segment = LBA * DISK_SECTOR_SIZE / 0x10 + DISK_IMAGE_SEGMENT
    mov cx, DISK_SECTOR_SIZE / 0x10 
    mul cx

    mov ds, ax

%ifdef DEBUG_DISK
    mov al, ah 
    call serial_print_hex

    mov ax, ds
    call serial_print_hex

    mov al, ' '
    call serial_putc
%endif

    ; Source address in DS:SI. Disk image must start at DS:0
    mov ax, ds
    add ax, DISK_IMAGE_SEGMENT
    mov ds, ax

    mov si, 0

    ; Set byte count to copy in CX
    pop ax ; recover original read count

%ifdef DEBUG_DISK
    call serial_print_hex
%endif

    mov cl, al

    push ax

    xor ch, ch
    mov ax, DISK_SECTOR_SIZE
    mul cx
    mov cx, ax

    ; ES:DI is destination
    mov di, bx

    ; DS:SI is source
    rep movsb

%ifdef DEBUG_DISK
    mov al, 13
    call serial_putc

    mov al, 10
    call serial_putc
%endif

    pop ax

    mov ah, 0

    pop si
    pop di
    pop ds
    pop cx

    clc
    jmp .done

.get_floppy_type:
    clc
    mov ah, 0
    cmp dl, 0
    je .done
    mov ah, 1
    jmp .done

.ignore:
    mov ah, 0;
    clc ; just say we are ok!

.done:
    retf 2 ; // instead of iret to overwrite flags.

