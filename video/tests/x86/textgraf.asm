CPU 8086
org 0x100

start:
    ; set graphics mode
    mov ax, 0x0004
    int 0x10

    xor dh, dh          ; row counter
fill_rows:
    mov dl, 0           ; cursor column 0
    mov bh, 0           ; page number 0
    mov ah, 0x02        ; set cursor position
    int 0x10

    mov al, dh          ; use row index for foreground color
    and al, 0x0F        ; use row index for foreground color
    mov cl, 4           ; shift to high nibble for attribute
    shl al, cl          
    mov bl, 0x0F        ; gray foreground color
    or bl, al
    mov ah, 0x09        ; write character and attribute
    mov al, dh
    add al, 'A'         ; character to print for this row
    mov bh, 0           ; page number 0
    mov cx, 40          ; fill full row
    int 0x10

    inc dh
    cmp dh, 25
    jb fill_rows

    mov ah, 0x4C
    mov al, 0x00
    int 0x21
