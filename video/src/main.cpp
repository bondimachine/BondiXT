#include "hardware/dma.h"
#include "hardware/pio.h"
#include <Arduino.h>
#include <cstdint>

// Include generated headers from the .pio files
// PlatformIO/pioasm will generate these automatically during build
#include "bus.pio.h"
#include "vga.pio.h"

/*
 * HARDWARE CONNECTIONS
 *  - GPIO 0-7 --> AD0-AD7
 *  - GPIO 8-16 -> A8-A16
 *  - GPIO 17 ---> 1k ohm resistor ---> VGA Red
 *  - GPIO 18 ---> 330 ohm resistor ---> VGA Red
 *  - GPIO 19 ---> 1k ohm resistor ---> VGA Green
 *  - GPIO 20 ---> 330 ohm resistor ---> VGA Green
 *  - GPIO 21 ---> 1k ohm resistor ---> VGA Blue
 *  - GPIO 22 ---> 330 ohm resistor ---> VGA Blue
 *  - GPIO 26 ---> VGA Hsync
 *  - GPIO 27 ---> VGA Vsync
 *  - GPIO 28 ---> /CS & /CLK
 *  - RP2040 GND ---> VGA GND
 */

// VGA timing constants
#define H_ACTIVE 655   // (active + frontporch - 1) - one cycle delay for mov
#define V_ACTIVE 479   // (active - 1)
// #define RGB_ACTIVE 319 // (horizontal active)/2 - 1
#define RGB_ACTIVE 639 // change to this if 1 pixel/byte

// Length of the pixel array, and number of DMA transfers
#define TXCOUNT 307200 // Total pixels (I could optimize this for 222 but oh well)

// Pixel color array that is DMA's to the PIO machines and
// a pointer to the ADDRESS of this color array.
// Note that this array is automatically initialized to all 0's (black)
unsigned char vga_data_array[TXCOUNT];
unsigned char *address_pointer = &vga_data_array[0];

// Pin Definitions
// Adjust these according to your hardware design
const uint8_t PIN_BUS_BASE = 0; // D0-D16
const uint8_t PIN_CS = 28;

const uint8_t PIN_VGA_HSYNC = 26;
const uint8_t PIN_VGA_VSYNC = 27;
const uint8_t PIN_VGA_RGB_BASE = 17; // R, R+, G, G+, B, B+ (6 pins)

// Global PIO variables for Bus Interface
PIO pio_bus = pio0;
int sm_bus = -1;

void demo(int color);

void setup() {
  Serial.begin(115200);
  Serial.println("BondiXT Video Card Initializing...");

  // --- Bus Interface Initialization ---
  // Using PIO0 for the Bus Interface
  // pio_bus is global
  unsigned int offset_bus = pio_add_program(pio_bus, &bus_program);
  sm_bus = pio_claim_unused_sm(pio_bus, true);

  if (sm_bus == -1) {
    Serial.println("Error: Could not claim State Machine for Bus Interface");
    return;
  }

  bus_program_init(pio_bus, sm_bus, offset_bus, PIN_BUS_BASE);
  Serial.println("Bus Interface Initialized");

  // --- VGA Initialization ---
  // Using PIO1 for VGA signals to keep them separate and avoid contention
  PIO pio_vga = pio1;

  uint hsync_offset = pio_add_program(pio_vga, &hsync_program);
  uint vsync_offset = pio_add_program(pio_vga, &vsync_program);
  uint rgb_offset = pio_add_program(pio_vga, &rgb_program);

  uint hsync_sm = 0;
  uint vsync_sm = 1;
  uint rgb_sm = 2;

  hsync_program_init(pio_vga, hsync_sm, hsync_offset, PIN_VGA_HSYNC);
  vsync_program_init(pio_vga, vsync_sm, vsync_offset, PIN_VGA_VSYNC);
  rgb_program_init(pio_vga, rgb_sm, rgb_offset, PIN_VGA_RGB_BASE);

  // DMA channels - 0 sends color data, 1 reconfigures and restarts 0
  int rgb_chan_0 = 0;
  int rgb_chan_1 = 1;

  // Channel Zero (sends color data to PIO VGA machine)
  dma_channel_config c0 =
      dma_channel_get_default_config(rgb_chan_0);         // default configs
  channel_config_set_transfer_data_size(&c0, DMA_SIZE_8); // 8-bit txfers
  channel_config_set_read_increment(&c0, true);   // yes read incrementing
  channel_config_set_write_increment(&c0, false); // no write incrementing
  channel_config_set_dreq(&c0, DREQ_PIO1_TX2);    // DREQ_PIO0_TX2 pacing (FIFO)
  channel_config_set_chain_to(&c0, rgb_chan_1);   // chain to other channel

  dma_channel_configure(
      rgb_chan_0,            // Channel to be configured
      &c0,                   // The configuration we just created
      &pio_vga->txf[rgb_sm], // write address (RGB PIO TX FIFO)
      &vga_data_array,       // The initial read address (pixel color array)
      TXCOUNT, // Number of transfers; in this case each is 1 byte.
      false    // Don't start immediately.
  );

  // Channel One (reconfigures the first channel)
  dma_channel_config c1 =
      dma_channel_get_default_config(rgb_chan_1);          // default configs
  channel_config_set_transfer_data_size(&c1, DMA_SIZE_32); // 32-bit txfers
  channel_config_set_read_increment(&c1, false);  // no read incrementing
  channel_config_set_write_increment(&c1, false); // no write incrementing
  channel_config_set_chain_to(&c1, rgb_chan_0);   // chain to other channel

  dma_channel_configure(
      rgb_chan_1, // Channel to be configured
      &c1,        // The configuration we just created
      &dma_hw->ch[rgb_chan_0]
           .read_addr,  // Write address (channel 0 read address)
      &address_pointer, // Read address (POINTER TO AN ADDRESS)
      1,                // Number of transfers, in this case each is 4 byte
      false             // Don't start immediately.
  );

  /////////////////////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////////////////////////////////////////////////

  // Initialize PIO state machine counters. This passes the information to the
  // state machines that they retrieve in the first 'pull' instructions, before
  // the .wrap_target directive in the assembly. Each uses these values to
  // initialize some counting registers.
  pio_sm_put_blocking(pio_vga, hsync_sm, H_ACTIVE);
  pio_sm_put_blocking(pio_vga, vsync_sm, V_ACTIVE);
  pio_sm_put_blocking(pio_vga, rgb_sm, RGB_ACTIVE);

  // Start the two pio machine IN SYNC
  // Note that the RGB state machine is running at full speed,
  // so synchronization doesn't matter for that one. But, we'll
  // start them all simultaneously anyway.
  pio_enable_sm_mask_in_sync(
      pio_vga, ((1u << hsync_sm) | (1u << vsync_sm) | (1u << rgb_sm)));

  // Start DMA channel 0. Once started, the contents of the pixel color array
  // will be continously DMA's to the PIO machines that are driving the screen.
  // To change the contents of the screen, we need only change the contents
  // of that array.
  dma_start_channel_mask((1u << rgb_chan_0));

  Serial.println("VGA Interface Initialized");

  demo(0);
}

// this is BBGGRR copied from CGA palette (ish)
#define BLACK 0b00000000
#define BLUE 0b00100000
#define GREEN 0b00001000
#define CYAN 0b001010000
#define RED 0b00000010
#define MAGENTA 0b00110011
#define BROWN 0b00011111
#define LIGHT_GRAY 0b00101010
#define DARK_GRAY 0b00010101
#define LIGHT_BLUE 0b00110101
#define LIGHT_GREEN 0b00011101
#define LIGHT_CYAN 0b00111101
#define LIGHT_RED 0b00010111
#define LIGHT_MAGENTA 0b00110111
#define YELLOW 0b00011111
#define WHITE 0b00111111

const uint8_t CGA_PALETTE16[16] = {BLACK, BLUE, GREEN, CYAN, RED, MAGENTA, BROWN, LIGHT_GRAY, 
  DARK_GRAY, LIGHT_BLUE, LIGHT_GREEN, LIGHT_CYAN, LIGHT_RED, LIGHT_MAGENTA, YELLOW, WHITE};


// CGA Palette Definitions
// We only have 8 colors, so we map CGA colors to the closest available
const uint8_t CGA_PALETTE4_0[4] = {BLACK, GREEN, RED,
                                  YELLOW}; // Green, Red, Brown
const uint8_t CGA_PALETTE4_1[4] = {BLACK, CYAN, MAGENTA,
                                  WHITE}; // Cyan, Magenta, White



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

// Update CGA Memory Byte
// offset: 0x0000 - 0x3FFF (16KB CGA Memory)
// val: 8-bit value containing 4 pixels (2 bits each)
void updateCGAByte(uint16_t offset, uint8_t val) {
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
    uint8_t pixel_val = (val >> (6 - (i * 2))) & 0x03;
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

// Process Bus Writes from PIO FIFO
void processBus(PIO pio, uint sm) {
  // Check if FIFO is not empty
  while (!pio_sm_is_rx_fifo_empty(pio, sm)) {
    uint32_t data = pio_sm_get(pio, sm);

    // Format from bus.pio:
    // ISR = [Address (16) << 8 | Data (8)]

    uint8_t value = data & 0xFF;
    uint32_t full_address = ((data >> 8) & 0x1FFFF) + 0xA0000;
    uint16_t address = full_address & 0xFFFF;

    Serial.print("Address: ");
    Serial.println(address, HEX);
    Serial.print("Value: ");
    Serial.println(value, HEX);

    if (address < 0xB0000) {
      // TODO: Support mode 10h
      // MCGA / VGA at A0000 (13h)
      // Ignore
    } else if (address < 0xB8000) {
      // We are mapping B0000 - B7FFF which is Hercules space as I/O
      // TODO: Support IO addresses at 0x3B0 - 0x3DF (CGA)
      // TODO: Support IO addresses EGA/VGA at 0x3C0 - 0x3DF?
    } else {
      // TODO: Support Text (02h)
      // TOOD: Support high res mono CGA (06h)?
      updateCGAByte(address, value);
    }
  }
}

void demo(int color) {
  int x = 0; // VGA x coordinate
  int y = 0; // VGA y coordinate

  // A couple of counters
  int xcounter = 0;
  int ycounter = 0;

  for (y = 0; y < 480; y++) {  // For each y-coordinate . . .
    if (ycounter == 8) {      //   If the y-counter is 60 . . .
      ycounter = 0;            //     Zero the counter
      color = (color + 1) % 64; //     Increment the color index
    } //
    ycounter += 1;               //   Increment the y-counter
    for (x = 0; x < 640; x++) {  //   For each x-coordinate . . .
      if (xcounter == 10) {      //     If the x-counter is 80 . . .
        xcounter = 0;            //        Zero the x-counter
        color = (color + 1) % 64; //        Increment the color index
      } //
      xcounter += 1;                  //     Increment the x-counter
      drawPixel(x, y, color); //     Draw a pixel to the screen
    }
  }
}


// void fullcolor(uint8_t color) {
//     for (int y = 0; y < 480; y++) {  // For each y-coordinate . . .
//       for (int x = 0; x < 640; x++) {  //   For each x-coordinate . . .
//         drawPixel(x, y, color); //     Draw a pixel to the screen
//       }
//     }
// }

int color = 0; 
void loop() {
  // processBus(pio_bus, sm_bus);
  demo(color);
  color = (color + 1) % 64;
}
