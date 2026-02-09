# BondiXT

8088 based computer on a breadboard

## Features

- Minimal ROM BIOS
- Console emulation thru serial port using 8251.
- Floppy emulation from ROM stored image
- Boots to DOS 3.3 and 5.0 (from ROM)
- CGA and basic EGA/EGA video output to VGA monitor using a Rapsberry Pi Pico RP2350
- Glue logic using GAL20V8
- Poor man's Parallel port using a 74LS377 latch and 74LS245 buffer

### TODO
- Test SD card support thru SD.SYS via the parallel port
- 8253 PIT timer support & PC speaker (either real or emulated) 
- PIC 8259A interrupt controller (TBD, only if absolutely necessary)
- Keyboard emulation (via Arduino Nano? or separated pi pico). Then mouse (or serial mouse)
- Video BIOS to support console emulation on the Pico (cursor position, scrolling). Text mode "framebuffer" works already.
- Run some games!


## Supported interrupts

Minimal interrupts we need to support for DOS 3.3 (from DOS source code, need to validate which ones we can survive without)

```
    int 10h 0Eh | video write char teletype
    int 11h     | get equipment list
    int 12h     | get memory size
    int 13h 00h | reset disk drives  
    int 13h 02h | read sectors
    int 13h 08h | get drive parameters
    int 13h 15h | get drive type
    int 13h 16h | get floppy drive media change status
    int 13h 18h | set floppy drive media type
    int 14h 00h | serial port initialization 
    int 14h 01h | serial port transmit char
    int 14h 02h | serial port receive char
    int 14h 03h | serial port status
    int 15h C0h | get system parameters 
    int 15h 41h | wait for external event (PC Convertible) -> Ignore
    int 15h 90h | wait for disk interrupt
    int 16h 00h | keyboard read char
    int 16h 01h | keyboard read input status
    int 17h 1h  | initialize printer
    int 17h 2h  | check printer status
    int 19h     | (re)boot
    int 1ah 00h | read RTC
    int 1ah 01h | set RTC
    int 1ah 02h | read RTC time
    int 1ah 03h | set RTC time
    int 1ah 05h | set RTC date
    int 1eh     | diskette parameter table
    int 46h     | fixed dist parameter table (2nd drive, why not first?)
    int 70h     | irq8: called from RTC
```