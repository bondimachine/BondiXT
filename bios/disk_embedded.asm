int13_handler:
    pusha

    push    ax
    xor     bx, bx          ; zero BX → BL will hold AH
    mov     bl, ah          ; BL = AH
    shl     bx, 1           ; BX = BL * 2  (index * 2 bytes)

    cmp     bx, .ah_count
    jae     .ignore

    jmp     word [.ah_table + bx] 

.ah_table:
    dw  .ignore ; 00h reset
    dw  .get_drive_parameters ; 01h
    dw  .read_sectors ; 02h
    dw  .ignore ; 03h write sector. WE ARE A ROM!
    dw  .ignore ; 04h verify sector.
    dw  .ignore ; 05h format track
    dw  .read_sectors ; 06h read with retry
    dw  .ignore ; 07h write with retry
    dw  .ignore ; 08h 
    dw  .ignore ; 09h 
    dw  .ignore ; 10h 
    dw  .ignore ; 11h 
    dw  .ignore ; 12h 
    dw  .ignore ; 13h 
    dw  .ignore ; 14h 
    dw  .ignore ; 15h get drive type 
    dw  .ignore ; 16h get floppy drive media change status
    dw  .ignore ; 17h 
    dw  .ignore ; 18h set floppy drive media type

.ah_count  equ 19*2          

.get_drive_parameters:
        ; TODO
        ; AH = status; AL = number of drives; CH = max head, CL = sector/track, DH = max head, DL = drive #, other regs contain cylinder/sector limits
        jmp     .done

.read_sectors:
        ; AL = #sectors, CH = cylinder low, CL = sector number & high bits, DH = head, DL = drive, ES:BX = buffer
        jmp     .done



.ignore:
    clc ; just say we are ok!

.done:
    popa
    iret
