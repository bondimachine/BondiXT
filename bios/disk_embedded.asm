int13_handler:
    pusha

    ; define disk geometry
    DISK_CYLINDERS      equ 40
    DISK_HEADS          equ 1
    DISK_SECTORS        equ 8
    DISK_SECTOR_SIZE    equ 512

    push    ax
    xor     bx, bx          ; zero BX → BL will hold AH
    mov     bl, ah          ; BL = AH
    shl     bx, 1           ; BX = BL * 2  (index * 2 bytes)

    cmp     bx, .ah_count
    jae     .ignore

    jmp     word [.ah_table + bx] 

.ah_table:
    dw  .ignore     ; 00h reset
    dw  .ignore     ; 01h get last operation status
    dw  .read_sectors ; 02h
    dw  .ignore     ; 03h write sector. WE ARE A ROM!
    dw  .ignore     ; 04h verify sector.
    dw  .ignore     ; 05h format track
    dw  .read_sectors ; 06h read with retry
    dw  .ignore     ; 07h write with retry
    dw  .get_drive_parameters ; 08h get drive parameters
    dw  .ignore     ; 09h 
    dw  .ignore     ; 10h 
    dw  .ignore     ; 11h 
    dw  .ignore     ; 12h 
    dw  .ignore     ; 13h 
    dw  .ignore     ; 14h 
    dw  .get_floppy_type  ; 15h get drive type 
    dw  .ignore     ; 16h get floppy drive media change status
    dw  .ignore     ; 17h 
    dw  .ignore     ; 18h set floppy drive media type

.ah_count  equ 19*2          

.reset:
    clc
    jmp .done

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
    cmp dl, 0x80
    jne .done

    ; Calculate LBA address
    ; LBA = (cylinder * number_of_heads + head) * sectors_per_track + (sector - 1)
    
    ; DI = cylinder * number_of_heads
    xor ax, ax
    mov al, ch ; cylinder
    mov cl, DISK_HEADS
    mul cl
    mov di, ax

    ; DI += head
    xor ch, ch ; clear high bits of cx
    mov cl, dh ; head
    add di, cx

    ; DI *= sectors_per_track
    mov ax, di
    mov cl, DISK_SECTORS
    mul cl
    mov di, ax

    ; DI += sector - 1
    mov cl, byte [bp-2] ; CL from original CX before pusha
    and cl, 0x3F ; sector is in lower 6 bits
    xor ch, ch
    dec cx
    add di, cx

    ; DI is now LBA, calculate memory offset
    ; offset = LBA * 512
    mov ax, di
    mov cx, DISK_SECTOR_SIZE
    mul cx
    mov si, ax
    add si, word [bp+0] ; high word of LBA * 512
    
    ; Source address in DS:SI
    push ds
    mov ax, DISK_IMAGE_SEGMENT
    mov ds, ax
    and si, 0xFFFF

    ; Set byte count to copy
    mov cl, byte [bp-10] ; AL from original AX
    xor ch, ch
    mov ax, DISK_SECTOR_SIZE
    mul cx
    mov cx, ax

    ; ES:BX is destination
    ; DS:SI is source
    rep movsb

    pop ds
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
    popa
    iret
