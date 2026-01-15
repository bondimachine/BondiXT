#define FRAME_BUFFER_SIZE 307200 // Total pixels (I could optimize this for 222 but oh well)

// Pixel color array that is DMA's to the PIO machines and
// a pointer to the ADDRESS of this color array.
// Note that this array is automatically initialized to all 0's (black)
unsigned char vga_data_array[FRAME_BUFFER_SIZE];
unsigned char *address_pointer = &vga_data_array[0];


// this is BBGGRR copied from CGA palette (ish)
#define BLACK         0b00000000
#define BLUE          0b00100000
#define GREEN         0b00001000
#define CYAN          0b00101000
#define RED           0b00000010
#define MAGENTA       0b00110011
#define BROWN         0b00011111
#define LIGHT_GRAY    0b00101010
#define DARK_GRAY     0b00010101
#define LIGHT_BLUE    0b00110101
#define LIGHT_GREEN   0b00011101
#define LIGHT_CYAN    0b00111101
#define LIGHT_RED     0b00010111
#define LIGHT_MAGENTA 0b00110111
#define YELLOW        0b00011111
#define WHITE         0b00111111

const uint8_t CGA_PALETTE16[16] = {BLACK, BLUE, GREEN, CYAN, RED, MAGENTA, BROWN, LIGHT_GRAY, 
  DARK_GRAY, LIGHT_BLUE, LIGHT_GREEN, LIGHT_CYAN, LIGHT_RED, LIGHT_MAGENTA, YELLOW, WHITE};


// CGA Palette Definitions
// We only have 8 colors, so we map CGA colors to the closest available
const uint8_t CGA_PALETTE4_0[4] = {BLACK, GREEN, RED,
                                  YELLOW}; // Green, Red, Brown
const uint8_t CGA_PALETTE4_1[4] = {BLACK, CYAN, MAGENTA,
                                  WHITE}; // Cyan, Magenta, White


#include "vga_palette.h"

// Current palette selection (0 or 1)
uint8_t current_palette_idx = 1;

// Helper to get color from current palette
uint8_t getCGAColor(uint8_t color_idx) {
  if (current_palette_idx == 0) {
    return CGA_PALETTE4_0[color_idx & 3];
  } else {
    return CGA_PALETTE4_1[color_idx & 3];
  }
}

// A function for drawing a pixel with a specified color.
// Note that because information is passed to the PIO state machines through
// a DMA channel, we only need to modify the contents of the array and the
// pixels will be automatically updated on the screen.
void drawPixel(int x, int y, uint8_t color) {
  // Range checks
  if (x > 639)
    x = 639;
  if (x < 0)
    x = 0;
  if (y < 0)
    y = 0;
  if (y > 479)
    y = 479;

  // Which pixel is it?
  int pixel = ((640 * y) + x);

  vga_data_array[pixel] = color;
}

void updateCGAByte(uint16_t offset, uint8_t val) {

  // TODO: Support Text (02h)
  // TOOD: Support high res mono CGA (06h)?

  // Update CGA Memory Byte
  // offset: 0x0000 - 0x3FFF (16KB CGA Memory)
  // val: 8-bit value containing 4 pixels (2 bits each)

  // CGA Memory Layout:
  // Bank 0 (Even lines): 0x0000 - 0x1FFF
  // Bank 1 (Odd lines):  0x2000 - 0x3FFF
  // Line width: 80 bytes (320 pixels)

  int cga_y;
  int cga_x_byte;

  if (offset < 0x2000) {
    // Bank 0 (Even lines)
    cga_y = (offset / 80) * 2;
    cga_x_byte = offset % 80;
  } else {
    // Bank 1 (Odd lines)
    cga_y = ((offset - 0x2000) / 80) * 2 + 1;
    cga_x_byte = (offset - 0x2000) % 80;
  }

  // Each byte contains 4 pixels: P0 P1 P2 P3 (High bits -> Low bits)
  // P0: bits 7-6
  // P1: bits 5-4
  // P2: bits 3-2
  // P3: bits 1-0

  for (int i = 0; i < 4; i++) {
    uint8_t pixel_val = (val >> (6 - (i * 2))) & 0b11;
    uint8_t color = getCGAColor(pixel_val);

    int cga_x = cga_x_byte * 4 + i;

    // Scale to VGA (2x)
    // CGA 320x200 -> VGA 640x400
    // Each CGA pixel becomes a 2x2 VGA block
    int vga_x = cga_x * 2;
    int vga_y = cga_y * 2;

    drawPixel(vga_x, vga_y, color);
    drawPixel(vga_x + 1, vga_y, color);
    drawPixel(vga_x, vga_y + 1, color);
    drawPixel(vga_x + 1, vga_y + 1, color);
  }
}

void updateVGAByte(uint16_t offset, uint8_t val) {

  // TODO: Support mode 10h

  // VGA Mode 13h: 320x200, 256 colors
  // Each byte represents one pixel

  int vga_x = offset % 320;
  int vga_y = offset / 320;

  // Scale to VGA (2x)
  // VGA 320x200 -> VGA 640x400
  // Each pixel becomes a 2x2 block
  int scaled_x = vga_x * 2;
  int scaled_y = vga_y * 2;

  uint8_t color = vga_palette_6bit[val]; // Direct mapping for 256-color mode

  drawPixel(scaled_x, scaled_y, color);
  drawPixel(scaled_x + 1, scaled_y, color);
  drawPixel(scaled_x, scaled_y + 1, color);
  drawPixel(scaled_x + 1, scaled_y + 1, color);

}  

void processMemoryBusMessage(uint32_t address, uint8_t value) {
  if (address < 0xB0000) {
    updateVGAByte(address - 0xA0000, value);
  } else if (address < 0xB8000) {
    // We are mapping B0000 - B7FFF which is Hercules space as I/O
    // TODO: Support IO addresses at 0x3B0 - 0x3DF (CGA)
    // TODO: Support IO addresses EGA/VGA at 0x3C0 - 0x3DF?
  } else {
    updateCGAByte(address - 0xB8000, value);
  }
}
