#include <Arduino.h>
#include <AnimatedGIF.h>
#include <LittleFS.h>

// Pin Definitions
const uint8_t PIN_BUS_BASE = 0; // D0-D15
const uint8_t PIN_CS = 26; // PI Zero doesn't have 16-25 pins
const uint8_t PIN_WR = 27;

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
void bus_write(uint16_t address, uint8_t data) {
    // 1. Set Address (Pins 0-15)
    gpio_put_masked(0xFFFF, address);
    
    // 2. Assert CS (Low)
    // Receiver reads Address immediately after CS goes low
    gpio_put(PIN_CS, 0);
    

    __asm ("nop; nop; nop; nop; nop; nop; nop; nop; ");
    
    // 3. Set Data (Pins 0-7)
    // This overwrites the lower byte of the address on the bus,
    // but the receiver should have already sampled the address.
    gpio_put_masked(0xFF, data);
    
    // 4. Assert WR (Low)
    // Receiver waits for WR low then reads Data
    gpio_put(PIN_WR, 0);
    
    __asm ("nop; nop; nop; nop; nop; nop; nop; nop; ");
    
    // 5. Deassert WR (High)
    gpio_put(PIN_WR, 1);
    
    __asm ("nop; nop; nop; nop; nop; nop; nop; nop; ");

    // 6. Deassert CS (High)
    gpio_put(PIN_CS, 1);
}

// Draw Callback
void GIFDraw(GIFDRAW *pDraw) {
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
        uint8_t p0 = (i < width) ? (s[i] % 4) : 0;
        uint8_t p1 = (i + 1 < width) ? (s[i+1] % 4) : 0;
        uint8_t p2 = (i + 2 < width) ? (s[i+2] % 4) : 0;
        uint8_t p3 = (i + 3 < width) ? (s[i+3] % 4) : 0;

        uint8_t val = (p0 << 6) | (p1 << 4) | (p2 << 2) | p3;

        // Calculate CGA Address
        // Bank 0 (Even y): (y/2)*80 + x_byte
        // Bank 1 (Odd y):  0x2000 + (y/2)*80 + x_byte
        
        int current_x = x + i;
        int x_byte = current_x / 4;
        
        uint16_t address;
        if (y % 2 == 0) {
            address = (y / 2) * 80 + x_byte;
        } else {
            address = 0x2000 + (y / 2) * 80 + x_byte;
        }
        
        bus_write(address, val);
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
    // CS, WR
    gpio_init(PIN_CS);
    gpio_set_dir(PIN_CS, GPIO_OUT);
    gpio_put(PIN_CS, 1); // Default High

    gpio_init(PIN_WR);
    gpio_set_dir(PIN_WR, GPIO_OUT);
    gpio_put(PIN_WR, 1); // Default High
    
    Serial.println("Bus Interface Initialized (Bit-banged)");

    // Initialize GIF
    gif.begin(LITTLE_ENDIAN_PIXELS);
    
    // Initialize LittleFS
    if (!LittleFS.begin()) {
        Serial.println("LittleFS mount failed");
        return;
    }
    Serial.println("LittleFS mounted");
}

void play(const char *szFilename) {
    if (gif.open(szFilename, GIFOpenFile, GIFCloseFile, GIFReadFile, GIFSeekFile, GIFDraw)) {
        Serial.printf("GIF Opened. Canvas: %dx%d\n", gif.getCanvasWidth(), gif.getCanvasHeight());
        int lastResult = 0;
        while ((lastResult = gif.playFrame(true, NULL)) > 0) {
            // Playing
            Serial.println("frame");
        }
        if (lastResult == 0) {
            Serial.println("GIF Playback Completed");
        } else {
            Serial.print("GIF Playback Error ");
            Serial.println(gif.getLastError());
        }
        gif.close();
        Serial.println("GIF Finished. Restarting...");
        delay(1000);
    } else {
        Serial.println("Error opening GIF");
        delay(5000);
    }
}

void loop() {
    play("/stan.gif");
}

