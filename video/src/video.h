#define FRAME_BUFFER_SIZE 307200 // Total pixels (I could optimize this for 222 but oh well)

// Pixel color array that is DMA's to the PIO machines and
// a pointer to the ADDRESS of this color array.
// Note that this array is automatically initialized to all 0's (black)
unsigned char vga_data_array[FRAME_BUFFER_SIZE];
unsigned char *address_pointer = &vga_data_array[0];

// VGA video mode - 0x10 for mode 10h, 0x13 for mode 13h
uint8_t current_video_mode = 0x13;


// VGA register emulation for mode 10h
uint8_t vga_write_plane_mask = 0x0F;  // Sequencer Map Mask Register (index 2) - all planes enabled by default

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

// Reverse lookup: 6-bit color (0-63) -> 4-bit palette index (0-15)
// Precomputed for O(1) lookup. Unmapped colors default to 0 (BLACK).
// Mappings: BLACK=0, BLUE=32, GREEN=8, CYAN=40, RED=2, MAGENTA=51, BROWN=31,
//           LIGHT_GRAY=42, DARK_GRAY=21, LIGHT_BLUE=53, LIGHT_GREEN=29,
//           LIGHT_CYAN=61, LIGHT_RED=23, LIGHT_MAGENTA=55, YELLOW=31, WHITE=63
const uint8_t CGA_PALETTE16_REVERSE[64] = {
//  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
    0,  0,  4,  0,  0,  0,  0,  0,  2,  0,  0,  0,  0,  0,  0,  0,  // 0-15
    0,  0,  0,  0,  0,  8,  0, 12,  0,  0,  0,  0,  0, 10,  0,  6,  // 16-31  (21=DARK_GRAY, 23=LIGHT_RED, 29=LIGHT_GREEN, 31=BROWN/YELLOW)
    1,  0,  0,  0,  0,  0,  0,  0,  3,  0,  7,  0,  0,  0,  0,  0,  // 32-47  (32=BLUE, 40=CYAN, 42=LIGHT_GRAY)
    0,  0,  0,  5,  0,  9,  0, 13,  0,  0,  0,  0,  0, 11,  0, 15,  // 48-63  (51=MAGENTA, 53=LIGHT_BLUE, 55=LIGHT_MAGENTA, 61=LIGHT_CYAN, 63=WHITE)
};

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

  // Update CGA Memory Byte
  // offset: 0x0000 - 0x3FFF (16KB CGA Memory)
  // val: 8-bit value containing 4 pixels OR 8 pixels depending on mode

  // CGA Memory Layout:
  // Bank 0 (Even lines): 0x0000 - 0x1FFF
  // Bank 1 (Odd lines):  0x2000 - 0x3FFF
  // Line width: 80 bytes (320/640 pixels)

  int cga_y;
  int cga_x_byte;

  if (current_video_mode == 0x6) {
    // CGA Graphics Mode 6: 640x200, 2 colors (1 bit per pixel)
    // Each byte contains 8 pixels: P0 P1 P2 P3 P4 P5 P6 P7 (High bits -> Low bits)

    cga_y = (offset / 80);
    cga_x_byte = offset % 80;
    for (int i = 0; i < 8; i++) {
      uint8_t pixel_val = (val >> (7 - i)) & 0b1;
      uint8_t color = pixel_val ? WHITE : BLACK;

      int cga_x = cga_x_byte * 8 + i;

      // Scale to VGA (2x)
      // CGA 640x200 -> VGA 640x400
      // Each CGA pixel becomes a 1x2 VGA block
      int vga_x = cga_x;
      int vga_y = cga_y * 2;

      drawPixel(vga_x, vga_y, color);
      drawPixel(vga_x, vga_y + 1, color);
    }
  } else {
    if (offset < 0x2000) {
      // Bank 0 (Even lines)
      cga_y = (offset / 80) * 2;
      cga_x_byte = offset % 80;
    } else {
      // Bank 1 (Odd lines)
      cga_y = ((offset - 0x2000) / 80) * 2 + 1;
      cga_x_byte = (offset - 0x2000) % 80;
    }

    // CGA Graphics Mode 4: 320x200, 4 colors (2 bits per pixel)}
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
}

void updateVGAByte(uint16_t offset, uint8_t val) {
  if (current_video_mode == 0x10 || current_video_mode == 0x12) {
    // VGA Mode 10h: 640x350, 16 colors, 4 bit planes
    // VGA Mode 12h: 640x480, 16 colors, 4 bit planes
    // Both use identical planar memory organization:
    // - Each address in video memory maps to the same offset in all 4 planes
    // - The vga_write_plane_mask determines which planes are written
    // - Each byte represents 8 consecutive horizontal pixels
    // - The color of each pixel is determined by combining bits from all 4 planes

    int max_rows = (current_video_mode == 0x12) ? 480 : 350;

    // Calculate the starting pixel position
    // 640 pixels wide, so 80 bytes per row
    int byte_x = offset % 80;  // Which byte in the row (0-79)
    int pixel_y = offset / 80; // Which row
    int pixel_x_base = byte_x * 8; // Starting X position (each byte = 8 pixels)

    if (pixel_y >= max_rows) {
      return; // Out of visible area
    }

    // Update all 8 pixels represented by this byte
    for (int bit = 0; bit < 8; bit++) {
      int pixel_x = pixel_x_base + bit;
      int pixel_offset = pixel_y * 640 + pixel_x;
      
      // Bit 7 is leftmost pixel, bit 0 is rightmost
      int bit_position = 7 - bit;
      uint8_t incoming_bit = (val >> bit_position) & 1;
      
      // Read current pixel color and find its palette index using precomputed table
      uint8_t current_color = vga_data_array[pixel_offset];
      uint8_t current_index = CGA_PALETTE16_REVERSE[current_color & 0x3F];
      
      // Modify the bits for the planes being written
      uint8_t new_index = current_index;
      for (int plane = 0; plane < 4; plane++) {
        if (vga_write_plane_mask & (1 << plane)) {
          // Update this plane's bit with the incoming bit
          if (incoming_bit) {
            new_index |= (1 << plane);
          } else {
            new_index &= ~(1 << plane);
          }
        }
      }
      // Write the new color
      vga_data_array[pixel_offset] = CGA_PALETTE16[new_index];
    }
  } else {
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
}

void processIO(uint16_t address, uint8_t value) {
  switch (address) {
    case 0x3D8:
      // CGA Mode control register
      if (value & 0x2) { // graphics mode
        if (value & 0x8) {
          current_video_mode = 0x6; // 640x200 mono
        } else {
          current_video_mode = 0x4; // 320x200 color
        }
      } else { // text mode
        current_video_mode = 0x2; // 80x25 text
      }
      break;
    case 0x3D9:
      // CGA Color control register
      current_palette_idx = (value & 0x10);
      break;
    case 0x3C2: // Miscellaneous Output Register
      // this is really crappy, but kinda works
      if (value == 0xa3) {
        current_video_mode = 0x10;
      } else if (value == 0xe3) {
        current_video_mode = 0x12;
      } else {
        current_video_mode = 0x13;
      }
      break;
    case 0x3CF: 
      // graphics mode data register
      vga_write_plane_mask = value & 0x0F;
      break;
  }  
}

void processMemoryBusMessage(uint32_t address, uint8_t value) {
  if (address < 0xB0000) {
    updateVGAByte(address - 0xA0000, value);
  } else if (address < 0xB8000) {
    // We are mapping B0000 - B7FFF which is Hercules space as I/O
    processIO((uint16_t)(address - 0xB0000), value);
  } else {
    updateCGAByte(address - 0xB8000, value);
  }
}
