SERIAL_PORT EQU 0x3F8           ; COM1 base SERIAL_PORT
SERIAL_PORT_IER        EQU SERIAL_PORT + 1       ; Interrupt Enable Register
SERIAL_PORT_LCR        EQU SERIAL_PORT + 3       ; Line Control Register
SERIAL_PORT_MCR        EQU SERIAL_PORT + 4       ; Modem Control Register
SERIAL_PORT_LSR        EQU SERIAL_PORT + 5       ; Line Status Register
SERIAL_PORT_DIV_LOW    EQU SERIAL_PORT + 0       ; Divisor Latch Low Byte (when DLAB=1)
SERIAL_PORT_DIV_HIGH   EQU SERIAL_PORT + 1       ; Divisor Latch High Byte (when DLAB=1)

SERIAL_PORT_BAUD_DIVISOR    EQU 12 ; 9600
