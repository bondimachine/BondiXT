#include <Arduino.h>
#include <AnimatedGIF.h>
#include <LittleFS.h>
#define HALF_CLOCK() __asm ("nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop;")

// Pin Definitions
const uint8_t PIN_BUS_BASE = 0; // D0-D15
const uint8_t PIN_BUS_HIGH = 26; // PI Zero doesn't have 16-25 pins
const uint8_t PIN_CS = 28; // && CLK 

// AnimatedGIF Object
AnimatedGIF gif;
File gifFile;

// File Callbacks
void * GIFOpenFile(const char *fname, int32_t *pSize) {
  gifFile = LittleFS.open(fname, "r");
  if (gifFile) {
    *pSize = gifFile.size();
    return (void *)&gifFile;
  }
  return NULL;
}

void GIFCloseFile(void *pHandle) {
  File *f = (File *)pHandle;
  if (f != NULL)
     f->close();
}

int32_t GIFReadFile(GIFFILE *pFile, uint8_t *pBuf, int32_t iLen) {
    int32_t iBytesRead;
    iBytesRead = iLen;
    File *f = (File *)pFile->fHandle;
    // Note: If you read a file all the way to the last byte, seek() stops working
    if ((f->size() - f->position()) < iLen)
       iBytesRead = f->size() - f->position() - 1; // <-- ugly work-around
    if (iBytesRead <= 0) return 0;
    iBytesRead = (int32_t)f->read(pBuf, iBytesRead);
    pFile->iPos += iBytesRead;
    return iBytesRead;
}

int32_t GIFSeekFile(GIFFILE *pFile, int32_t iPosition) { 
  File *f = (File *)pFile->fHandle;
  pFile->iPos = iPosition;
  f->seek(iPosition);
  return iPosition;
}

// Helper to write to bus (Bit-banged)
void bus_write(uint32_t address, uint8_t data) {

    // Serial.print("processMemoryBusMessage(0x");
    // Serial.print(address, HEX);
    // Serial.print(", 0x");
    // Serial.print(data, HEX);
    // Serial.println(");");

    // t1 low
    gpio_put_masked(0xFFFF, address);    
    gpio_put(PIN_BUS_HIGH, (address >> 16) & 0x1);

    // t1 high
    gpio_put(PIN_CS, 0);
    HALF_CLOCK();

    // t2 low
    gpio_put(PIN_CS, 1);
    HALF_CLOCK();

    gpio_put_masked(0xFF, data);

    // t2 high
    gpio_put(PIN_CS, 0);
    HALF_CLOCK();

    // t3 low
    gpio_put(PIN_CS, 1);
    HALF_CLOCK();

    // t3 high
    gpio_put(PIN_CS, 0);
    HALF_CLOCK();

    // t4 
    gpio_put(PIN_CS, 1);
}

void bus_write_important(uint32_t address, uint8_t data) {
    for(int i = 0; i < 20; i++) {
        bus_write(address, data);
    }
}


uint8_t cga_color(uint8_t gif_pixel) {
    // colors are swapped in the palette. I wasted enough time trying to fix it. 
    if (gif_pixel == 1) 
        return 2;
    if (gif_pixel == 2)
        return 1;
    return gif_pixel;     
}

// Draw Callback
void GIFDrawCGA(GIFDRAW *pDraw) {
    if (pDraw->y == -1) return; // Header/Footer

    // Process line
    uint8_t *s = pDraw->pPixels;
    int x = pDraw->iX;
    int y = pDraw->y;
    int width = pDraw->iWidth;

    // We need to pack 4 pixels into a byte
    // CGA pixels are 2 bits each.
    // Byte: P0 P1 P2 P3 (High -> Low)
    
    // We assume we start at a byte boundary for simplicity in this test
    // If x is not multiple of 4, we might overwrite/read-modify-write, 
    // but here we are the master overwriting.
    
    for (int i = 0; i < width; i += 4) {
        // Collect 4 pixels
        uint8_t p0 = (i < width) ? (cga_color(s[i])) : 0;
        uint8_t p1 = (i + 1 < width) ? (cga_color(s[i+1])) : 0;
        uint8_t p2 = (i + 2 < width) ? (cga_color(s[i+2])) : 0;
        uint8_t p3 = (i + 3 < width) ? (cga_color(s[i+3])) : 0;

        uint8_t val = (p0 << 6) | (p1 << 4) | (p2 << 2) | p3;

        // Calculate CGA Address
        // Bank 0 (Even y): (y/2)*80 + x_byte
        // Bank 1 (Odd y):  0x2000 + (y/2)*80 + x_byte
        
        int current_x = x + i;
        int x_byte = current_x / 4;
        
        uint32_t address;
        if (y % 2 == 0) {
            address = ((y / 2) * 80 + x_byte) + 0xB8000;
        } else {
            address = (0x2000 + (y / 2) * 80 + x_byte) + 0xB8000;
        }
        
        bus_write(address, val);
    }
}

void GIFDrawVGA13h(GIFDRAW *pDraw) {
    if (pDraw->y == -1) return; // Header/Footer

    // Process line
    uint8_t *s = pDraw->pPixels;
    int x = pDraw->iX;
    int y = pDraw->y;
    int width = pDraw->iWidth;

    for (int i = 0; i < width; i++) {
        uint8_t val = s[i];
        uint32_t address = y * 320 + x + i + 0xA0000;        
        bus_write(address, val);
    }
}

void GIFDrawVGA12h(GIFDRAW *pDraw) {
    if (pDraw->y == -1) return; 

    // Process line
    uint8_t *s = pDraw->pPixels;
    int x = pDraw->iX;
    int y = pDraw->y;
    int width = pDraw->iWidth;

    int memory_x = x / 8;
    for (int plane = 0; plane < 4; plane++) {
        bus_write_important(0xB03CF, (1 << plane));

        for (int i = 0; i < width; i+=8, memory_x++) {
            // 8 pixels at a time
            // For each plane 0-3
            uint8_t vga_byte = 0;
            for (int bit = 0; bit < 8; bit++) {
                if (s[i+bit] & (1 << plane)) {
                    vga_byte |= (1 << (7 - bit));
                }
            }
                
            uint32_t addr = 0xA0000 + y * 80 + memory_x;
            
            bus_write(addr, vga_byte);
        }
    }
}

void GIFDrawCGAHiRes(GIFDRAW *pDraw) {
    if (pDraw->y == -1) return; // Header/Footer

    // Process line
    uint8_t *s = pDraw->pPixels;
    int x = pDraw->iX;
    int y = pDraw->y;
    int width = pDraw->iWidth;

    // We need to pack 8 pixels into a byte
    // CGA pixels are 2 bits each.
    // Byte: P0 P1 P2 P3 P4 P5 P6 P7 (High -> Low)
    
    // We assume we start at a byte boundary for simplicity in this test
    // If x is not multiple of 8, we might overwrite/read-modify-write, 
    // but here we are the master overwriting.
    
    for (int i = 0; i < width; i += 8) {
        uint8_t pixel_val = 0;
        for (int bit = 0; bit < 8; bit++) {
            pixel_val |= (s[i+bit] & 0b1) << (7-bit);
        }
        int current_x = x + i;
        int x_byte = current_x / 8;
        
        uint32_t address = (y * 80 + x_byte) + 0xB8000;
        
        bus_write(address, pixel_val);
    }
}


void setup() {
    Serial.begin(115200);
    // while(!Serial) delay(10);
    Serial.println("GIF Player Test Initializing...");

    // Initialize GPIOs
    // D0-D15
    for (int i = 0; i < 16; i++) {
        gpio_init(i);
        gpio_set_dir(i, GPIO_OUT);
    }

    // D16
    gpio_init(PIN_BUS_HIGH);
    gpio_set_dir(PIN_BUS_HIGH, GPIO_OUT);

    // CS
    gpio_init(PIN_CS);
    gpio_set_dir(PIN_CS, GPIO_OUT);
    gpio_put(PIN_CS, 1); // Default High
    
    Serial.println("Bus Interface Initialized (Bit-banged)");

    // Initialize GIF
    gif.begin(GIF_PALETTE_RGB888);
    
    // Initialize LittleFS
    if (!LittleFS.begin()) {
        Serial.println("LittleFS mount failed");
        return;
    }
    Serial.println("LittleFS mounted");
}

void play(const char *szFilename, GIF_DRAW_CALLBACK *pfnDraw) {
    if (gif.open(szFilename, GIFOpenFile, GIFCloseFile, GIFReadFile, GIFSeekFile, pfnDraw)) {
        Serial.printf("GIF Opened. Canvas: %dx%d\n", gif.getCanvasWidth(), gif.getCanvasHeight());
        int lastResult = 0;
        while ((lastResult = gif.playFrame(true, NULL)) > 0) {
            // Playing
            Serial.println("frame");
            delay(10);
        }
        if (lastResult == 0) {
            Serial.println("GIF Playback Completed");
        } else {
            Serial.print("GIF Playback Error ");
            Serial.println(gif.getLastError());
        }
        gif.close();
        Serial.println("GIF Finished. Restarting...");
    } else {
        Serial.println("Error opening GIF");
        delay(5000);
    }
}

void bus_test() {
    bus_write(0x0000, 0x00);
    delay(100);
    bus_write(0xFFFF, 0xFF);
    delay(100);
    bus_write(0x0000, 0x00);
    delay(100);
    bus_write(0x0001, 0x00);
    delay(1000);
    bus_write(0x0002, 0x00);
    delay(1000);
    bus_write(0x0004, 0x00);
    delay(1000);
    bus_write(0x0008, 0x00);
    delay(1000);
    bus_write(0x0010, 0x00);
    delay(1000);
    bus_write(0x0020, 0x00);
    delay(1000);
    bus_write(0x0040, 0x00);
    delay(1000);
    bus_write(0x0080, 0x00);
    delay(1000);
    bus_write(0x0100, 0x00);
    delay(1000);
    bus_write(0x0200, 0x00);
    delay(1000);
    bus_write(0x0400, 0x00);
    delay(1000);
    bus_write(0x0800, 0x00);
    delay(1000);
    bus_write(0x1000, 0x00);
    delay(1000);
    bus_write(0x2000, 0x00);
    delay(1000);
    bus_write(0x4000, 0x00);
    delay(1000);
    bus_write(0x8000, 0x00);
    delay(1000);
    bus_write(0x10000, 0x00);
    delay(1000);
    bus_write(0x00000, 0x01);
    delay(1000);
    bus_write(0x00000, 0x02);
    delay(1000);
    bus_write(0x00000, 0x04);
    delay(1000);
    bus_write(0x00000, 0x08);
    delay(1000);
    bus_write(0x00000, 0x10);
    delay(1000);
    bus_write(0x00000, 0x20);
    delay(1000);
    bus_write(0x00000, 0x40);
    delay(1000);
    bus_write(0x00000, 0x80);
    delay(1000);    
}

void loop() {
    // play("/stan_cga.gif", GIFDrawCGA);
    // play("/stan_vga.gif", GIFDrawVGA13h);
    #if MAX_WIDTH < 640
        #error "MAX_WIDTH must be at least 640 for VGA test"
    #endif
    // bus_write_important(0xB03c2, 0xe3);
    // play("/win31.gif", GIFDrawVGA12h);
    bus_write_important(0xB03d8, 0b1001);
    play("/simcity.gif", GIFDrawCGAHiRes);
}

