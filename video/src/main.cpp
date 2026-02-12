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
 *  - GPIO 8-14 -> A8-A14
 *  - GPIO 15 ---> A15 || I/O while T1, A16 while T2
 *  - GPIO 16 ---> CLK
 *  - GPIO 17 ---> 1k ohm resistor ---> VGA Red
 *  - GPIO 18 ---> 330 ohm resistor ---> VGA Red
 *  - GPIO 19 ---> 1k ohm resistor ---> VGA Green
 *  - GPIO 20 ---> 330 ohm resistor ---> VGA Green
 *  - GPIO 21 ---> 1k ohm resistor ---> VGA Blue
 *  - GPIO 22 ---> 330 ohm resistor ---> VGA Blue
 *  - GPIO 26 ---> VGA Hsync
 *  - GPIO 27 ---> VGA Vsync
 *  - GPIO 28 ---> /CS
 *  - RP2040 GND ---> VGA GND
 */

// VGA timing constants
#define H_ACTIVE 655   // (active + frontporch - 1) - one cycle delay for mov
#define V_ACTIVE 479   // (active - 1)
// #define RGB_ACTIVE 319 // (horizontal active)/2 - 1
#define RGB_ACTIVE 639 // change to this if 1 pixel/byte

#include "video.h"

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

// Using PIO1 for VGA signals to keep them separate and avoid contention
PIO pio_vga = pio1;

#define USE_BUS_DMA

#ifdef USE_BUS_DMA
int dma_channel_bus = -1;

#define BUS_BUFFER_SIZE 1024
#define BUS_BUFFER_SIZE_BITS 10
volatile uint32_t buffer_bus[BUS_BUFFER_SIZE]; //__attribute__((aligned(2*BUS_BUFFER_SIZE)));
uint16_t buffer_bus_read_index = 0;

// DMA IRQ Handler for Bus Interface
void on_buffer_bus_full() {

  dma_hw->ints0 = 1u << dma_channel_bus;
  dma_channel_set_write_addr(dma_channel_bus, buffer_bus, true);
}

#endif

int rgb_chan_0 = -1;
void rgb_dma_isr() {
  dma_hw->ints0 = 1u << rgb_chan_0;
  vsync_flag = true;
}

void io_isr(void) {
  // for the moment the only possible thing to read is VSYNC
  pio_bus->irq = 1 << 1; // Clear the interrupt
  gpio_set_dir(3, GPIO_OUT);
  gpio_put(3, vsync_flag);
}

void vsync_isr(void) {
  pio_vga->irq = 1 << 2; // Clear the interrupt
  vsync_flag = false;
}  

repeating_timer_t cursor_timer;

bool cursor_timer_callback(repeating_timer_t* ignored) {
  render_cursor(!cursor_state);
  return true;
}

void setup() {
  Serial.begin(115200);
  Serial.println("BondiXT Video Card Initializing...");

  // --- Bus Interface Initialization ---
  // Using PIO0 for the Bus Interface
  // pio_bus is global
  unsigned int offset_bus = pio_add_program(pio_bus, &bus_program);
  sm_bus = pio_claim_unused_sm(pio_bus, true);

  while (sm_bus < 0) {
    Serial.println("Error: Could not claim State Machine for Bus Interface");
  }

  gpio_init(3);
  bus_program_init(pio_bus, sm_bus, offset_bus, PIN_BUS_BASE);

  #ifdef USE_BUS_DMA
  // Setup dma for read
  dma_channel_bus = dma_claim_unused_channel(false);
  while (dma_channel_bus < 0) {
      Serial.println("No free dma channels");
  }
  dma_channel_config dma_config_bus = dma_channel_get_default_config(dma_channel_bus);
  channel_config_set_transfer_data_size(&dma_config_bus, DMA_SIZE_32);
  channel_config_set_read_increment(&dma_config_bus, false);
  channel_config_set_write_increment(&dma_config_bus, true);
  
  // enable irq for rx
  dma_channel_set_irq0_enabled(dma_channel_bus, true);

  // setup dma to read from pio fifo
  channel_config_set_dreq(&dma_config_bus, pio_get_dreq(pio_bus, sm_bus, false /* receive */));

  // channel_config_set_ring(&dma_config_bus, true /* write */, BUS_BUFFER_SIZE_BITS);
  
  buffer_bus[0] = 0;

  irq_set_exclusive_handler(DMA_IRQ_0, on_buffer_bus_full);
  irq_set_priority(DMA_IRQ_0, PICO_HIGHEST_IRQ_PRIORITY);
  irq_set_enabled(DMA_IRQ_0, true);

  // dma started
  dma_channel_configure(dma_channel_bus, &dma_config_bus, buffer_bus, &pio_bus->rxf[sm_bus], dma_encode_transfer_count(BUS_BUFFER_SIZE), true /* start*/); 
  #endif

  irq_set_enabled(PIO0_IRQ_1, false);
  irq_set_priority(PIO0_IRQ_1, PICO_HIGHEST_IRQ_PRIORITY+1);
  pio_set_irq1_source_enabled(pio0, pis_interrupt1, true);
  irq_set_exclusive_handler(PIO0_IRQ_1, io_isr);
  irq_set_enabled(PIO0_IRQ_1, true);

  Serial.println("Bus Interface Initialized");

  // --- VGA Initialization ---

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
  rgb_chan_0 = dma_claim_unused_channel(false);
  int rgb_chan_1 = dma_claim_unused_channel(false);

  while (rgb_chan_0 < 0 || rgb_chan_1 < 0) {
      Serial.println("No free dma channels");
  }

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
      FRAME_BUFFER_SIZE, // Number of transfers; in this case each is 1 byte.
      false    // Don't start immediately.
  );

  dma_channel_set_irq1_enabled(rgb_chan_0, true);
  irq_set_exclusive_handler(DMA_IRQ_1, rgb_dma_isr);
  irq_set_priority(DMA_IRQ_1, PICO_HIGHEST_IRQ_PRIORITY);
  irq_set_enabled(DMA_IRQ_1, true);
  
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

  irq_set_enabled(PIO1_IRQ_1, false);
  irq_set_priority(PIO1_IRQ_1, PICO_DEFAULT_IRQ_PRIORITY);
  pio_set_irq1_source_enabled(pio1, pis_interrupt2, true);
  irq_set_exclusive_handler(PIO1_IRQ_1, vsync_isr);
  irq_set_enabled(PIO1_IRQ_1, true);

  Serial.println("VGA Interface Initialized");
  
  text_buffer = (uint8_t *)calloc(80 * 25 * 2, 1); // Allocate text buffer for 80x25 characters, 2 bytes each (char + attribute)
  while (!text_buffer) {
    Serial.println("Error: Could not allocate text buffer");
  }

  add_repeating_timer_ms(500, cursor_timer_callback, NULL, &cursor_timer);
}

// Process Bus Writes from PIO FIFO. Full Core1 dedidated to it.
void loop1() {
  while(sm_bus < 0) {}
  while (true) {
    #ifdef USE_BUS_DMA
    uint32_t data = buffer_bus[buffer_bus_read_index];
    if (data == 0)  { // even a write of 0 at 0xA0000 will have a flag 1 at bit 24, so total 0 means no data
      continue;
    }
    buffer_bus[buffer_bus_read_index] = 0;
    buffer_bus_read_index = (buffer_bus_read_index + 1) % BUS_BUFFER_SIZE;
    #else
    uint32_t data = pio_sm_get_blocking(pio_bus, sm_bus);
    #endif

    // Format from bus.pio:
    // ISR = [Address (17) << 8 | Data (8)]

    uint8_t value = data & 0xFF;
    uint32_t a16 = ((data >> 8) & 0x1) << 16;
    uint32_t full_address = (((data >> 9) & 0xFFFF) | a16) + 0xA0000;

    // Serial.printf("Bus Write: Data: 0x%08X, Addr: 0x%05X, Valie: 0x%02X\n", data, full_address, value);

    processMemoryBusMessage(full_address, value);

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

// void vga_palette() {
//   int x = 0; // VGA x coordinate
//   int y = 0; // VGA y coordinate

//   // A couple of counters
//   int xcounter = 0;
//   int ycounter = 0;
//   int color_low = 0;
//   int color_high = 0;

//   for (y = 0; y < 480; y++) {  // For each y-coordinate . . .
//     if (ycounter == 30) {      //   If the y-counter is 60 . . .
//       ycounter = 0;            //     Zero the counter
//       color_high = (color_high + 1) % 16; //     Increment the color index
//     } //
//     ycounter += 1;               //   Increment the y-counter
//     for (x = 0; x < 640; x++) {  //   For each x-coordinate . . .
//       if (xcounter == 40) {      //     If the x-counter is 80 . . .
//         xcounter = 0;            //        Zero the x-counter
//         color_low = (color_low + 1) % 16; //        Increment the color index
//       } //
//       xcounter += 1;                  //     Increment the x-counter
//       drawPixel(x, y, vga_palette_6bit[color_high << 4 | color_low]); //     Draw a pixel to the screen
//     }
//   }
// }

// void fullcolor(uint8_t color) {
//     for (int y = 0; y < 480; y++) {  // For each y-coordinate . . .
//       for (int x = 0; x < 640; x++) {  //   For each x-coordinate . . .
//         drawPixel(x, y, color); //     Draw a pixel to the screen
//       }
//     }
// }

// int color = 0; 
void loop() {
  // demo(color);
  // color = (color + 1) % 64;
}
