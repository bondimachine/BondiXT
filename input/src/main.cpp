#include "hid_to_scancode.h"
#include <Arduino.h>

// PS2_ONLY (set via the pico_ps2_only env in platformio.ini): no USB host.
// Only the PS/2 keyboard port is used and the USB port works as a regular
// CDC serial port for the debug output (instead of the UART on pins 12/13).

#ifndef PS2_ONLY

#include <Adafruit_TinyUSB.h>

#if not(CFG_TUD_HID)
#error "No HID support"
#endif

Adafruit_USBH_Host USBHost;

#else

#define Serial1 Serial

#endif

#include "bus.pio.h"

/*
; Pins 0-7: D0-D7
; Pin 8: /CS (!A8 && !A9 && IO && !ALE)

; Pin 14: DT/R
; Pin 15: A2
; Pin 26: \WR & \RD
; Pin 27: Keyboard Interrupt
; Pin 28: PS/2 Keyboard Clock (optional)
; Pin 29: PS/2 Keyboard Data (optional)

; Feels weird but pinout was thought for having a Pi Pico Zero potentially
connected ; just with the side headers

; Pin 9: Mouse Interrupt (optional)
; Pin 10: PS/2 Mouse Clock (optional)
; Pin 11: PS/2 Mouse Data (optional)

*/

#define KEYBOARD_INTERRUPT_PIN 27
#define MOUSE_INTERRUPT_PIN 9
#define PS2_KBD_CLK_PIN 28
#define PS2_KBD_DATA_PIN 29
#define PS2_MOUSE_CLK_PIN 10
#define PS2_MOUSE_DATA_PIN 11

#include "ps2_translation.h"

void data_buf_write(uint8_t data, bool is_mouse);

// ---------------------------------------------------------------------------
// PS/2 port: receive (device -> Pico) and send (Pico -> device).
// The lines are open-drain: we only ever pull them low (output 0) or release
// them (input with pull-up). Never drive them high.
// ---------------------------------------------------------------------------

#define PS2_RAW_BUF_SIZE 64
#define PS2_TX_TIMEOUT_MS 30

enum Ps2TxState : uint8_t {
  PS2_TX_IDLE = 0,
  PS2_TX_INHIBIT, // we are holding CLK low ourselves; ignore those edges
  PS2_TX_SENDING, // device is clocking our bits out
};

struct Ps2Port {
  uint8_t clk_pin;
  uint8_t data_pin;

  volatile uint8_t buf[PS2_RAW_BUF_SIZE];
  volatile uint8_t head;
  volatile uint8_t tail;

  volatile uint8_t bit_count;
  volatile uint8_t data_byte;
  volatile uint8_t ones; // for the parity check
  volatile uint32_t last_us;

  volatile uint8_t tx_state;
  volatile uint16_t tx_bits; // data(0-7) | parity(8) | stop(9)
  volatile uint8_t tx_index;
  volatile int8_t tx_result; // 0 pending, 1 acked, -1 failed
  uint32_t tx_started_ms;
};

Ps2Port ps2_kbd_port = {PS2_KBD_CLK_PIN, PS2_KBD_DATA_PIN};
Ps2Port ps2_mouse_port = {PS2_MOUSE_CLK_PIN, PS2_MOUSE_DATA_PIN};

static inline void ps2_pull_low(uint pin) {
  gpio_put(pin, 0);
  gpio_set_dir(pin, GPIO_OUT);
}

static inline void ps2_release(uint pin) { gpio_set_dir(pin, GPIO_IN); }

static void ps2_push(Ps2Port &p, uint8_t val) {
  uint8_t next_head = (p.head + 1) % PS2_RAW_BUF_SIZE;
  if (next_head != p.tail) {
    p.buf[p.head] = val;
    p.head = next_head;
  }
}

static bool ps2_has_data(Ps2Port &p) { return p.head != p.tail; }

static uint8_t ps2_pop(Ps2Port &p) {
  if (p.head == p.tail)
    return 0;
  uint8_t val = p.buf[p.tail];
  p.tail = (p.tail + 1) % PS2_RAW_BUF_SIZE;
  return val;
}

// Starts sending a byte to the device. Only blocks for the ~100us CLK
// inhibit; the bits are clocked out from the ISR. Poll ps2_tx_poll().
static void ps2_send(Ps2Port &p, uint8_t byte) {
  uint8_t parity = 1; // odd parity
  for (uint8_t b = byte; b; b >>= 1) {
    parity ^= b & 1;
  }

  p.tx_state = PS2_TX_INHIBIT;
  ps2_pull_low(p.clk_pin);
  delayMicroseconds(120);
  ps2_pull_low(p.data_pin); // start bit

  p.tx_bits = byte | (parity << 8) | (1 << 9);
  p.tx_index = 0;
  p.tx_result = 0;
  p.tx_started_ms = millis();
  p.tx_state = PS2_TX_SENDING;
  ps2_release(p.clk_pin); // device now generates the clock
}

// Returns 0 while sending, 1 when the device acked the frame, -1 on failure
// (nothing clocking, or no ack bit).
static int8_t ps2_tx_poll(Ps2Port &p) {
  if (p.tx_state == PS2_TX_SENDING &&
      millis() - p.tx_started_ms > PS2_TX_TIMEOUT_MS) {
    noInterrupts();
    if (p.tx_state == PS2_TX_SENDING) {
      ps2_release(p.data_pin);
      ps2_release(p.clk_pin);
      p.tx_state = PS2_TX_IDLE;
      p.tx_result = -1;
    }
    interrupts();
  }
  return p.tx_result;
}

static void ps2_clock_isr(Ps2Port &p) {
  uint32_t now = micros();

  if (p.tx_state == PS2_TX_INHIBIT) {
    return;
  }
  if (p.tx_state == PS2_TX_SENDING) {
    p.last_us = now;
    // The device samples DATA on the rising edge, so set it on the falling.
    if (p.tx_index < 10) {
      if ((p.tx_bits >> p.tx_index) & 1) {
        ps2_release(p.data_pin);
      } else {
        ps2_pull_low(p.data_pin);
      }
      p.tx_index++;
    } else {
      // 11th clock: device pulls DATA low to ack
      p.tx_result = gpio_get(p.data_pin) == 0 ? 1 : -1;
      ps2_release(p.data_pin);
      p.tx_state = PS2_TX_IDLE;
      p.bit_count = 0;
    }
    return;
  }

  if (now - p.last_us > 2000) {
    p.bit_count = 0; // stale partial frame
  }
  p.last_us = now;

  uint8_t bit = gpio_get(p.data_pin);
  if (p.bit_count == 0) {
    if (bit == 0) { // start bit
      p.data_byte = 0;
      p.ones = 0;
      p.bit_count++;
    }
  } else if (p.bit_count <= 8) {
    if (bit) {
      p.data_byte |= (1 << (p.bit_count - 1));
      p.ones++;
    }
    p.bit_count++;
  } else if (p.bit_count == 9) { // parity: total ones must be odd
    if (bit) {
      p.ones++;
    }
    p.bit_count++;
  } else {
    if (bit == 1 && (p.ones & 1)) { // stop bit + parity ok
      ps2_push(p, p.data_byte);
    }
    p.bit_count = 0;
  }
}

void ps2_kbd_clock_isr() { ps2_clock_isr(ps2_kbd_port); }
void ps2_mouse_clock_isr() { ps2_clock_isr(ps2_mouse_port); }

// ---------------------------------------------------------------------------
// PS/2 device init / detection.
// At boot we send a reset (0xFF) so the device answers 0xFA + 0xAA (BAT)
// even when it was already powered before the Pico started (reflash, 'r'
// reboot). A mouse also sends its ID (0x00) and then needs 0xF4 to start
// streaming. Runs from loop() without blocking, so USBHost.task() keeps
// running and USB devices can enumerate in parallel; the 8042 emulation
// treats a USB or PS/2 device the same.
// ---------------------------------------------------------------------------

enum Ps2InitState : uint8_t {
  PS2_INIT_SEND_RESET,
  PS2_INIT_SENDING_RESET,
  PS2_INIT_WAIT_BAT,
  PS2_INIT_SEND_ENABLE, // mouse only
  PS2_INIT_SENDING_ENABLE,
  PS2_INIT_WAIT_ENABLE_ACK,
  PS2_INIT_RETRY_WAIT,
  PS2_INIT_DONE,
};

#define PS2_INIT_ATTEMPTS 3
#define PS2_BAT_TIMEOUT_MS 1000
#define PS2_ACK_TIMEOUT_MS 100
#define PS2_RETRY_DELAY_MS 250
#define PS2_PACKET_TIMEOUT_MS 20
// Boot detection gives up 1 s after power-on, so the BIOS (which waits up to
// 1 s for the self-test reply) gets an answer. Late devices still show up
// through hot plug (their power-on BAT).
#define PS2_BOOT_DEADLINE_MS 1000

struct Ps2Device {
  Ps2Port &port;
  const char *name;
  bool is_mouse;

  uint8_t state;
  uint8_t attempts;
  uint32_t since_ms;
  bool bat_seen;
  volatile bool connected;

  // mouse packet assembly
  uint8_t packet[3];
  uint8_t packet_len;
  uint32_t packet_ms;

  bool boot_done; // boot detection finished (the 1 s deadline applies)
};

Ps2Device ps2_kbd = {ps2_kbd_port, "keyboard", false};
Ps2Device ps2_mouse = {ps2_mouse_port, "mouse", true};

static const char *ps2_status(const Ps2Device &d) {
  if (d.state != PS2_INIT_DONE) {
    return "detecting";
  }
  return d.connected ? "yes" : "no";
}

static void ps2_init_restart_enable(Ps2Device &d) {
  // after a mouse BAT (power-on, hot plug or our reset) streaming is off
  d.attempts = 0;
  d.packet_len = 0;
  d.state = PS2_INIT_SEND_ENABLE;
}

// Stops a send in progress and releases the lines.
static void ps2_tx_abort(Ps2Port &p) {
  noInterrupts();
  if (p.tx_state != PS2_TX_IDLE) {
    ps2_release(p.data_pin);
    ps2_release(p.clk_pin);
    p.tx_state = PS2_TX_IDLE;
    p.tx_result = -1;
  }
  interrupts();
}

static void ps2_device_task(Ps2Device &d) {
  uint32_t now = millis();
  if (d.state == PS2_INIT_DONE) {
    d.boot_done = true;
  } else if (!d.boot_done && now > PS2_BOOT_DEADLINE_MS) {
    ps2_tx_abort(d.port);
    if (!d.connected) {
      Serial1.printf("No PS/2 %s\n", d.name);
    }
    d.state = PS2_INIT_DONE;
    d.boot_done = true;
    return;
  }
  switch (d.state) {
  case PS2_INIT_SEND_RESET:
    d.attempts++;
    d.bat_seen = false;
    ps2_send(d.port, 0xFF);
    d.state = PS2_INIT_SENDING_RESET;
    break;
  case PS2_INIT_SENDING_RESET: {
    int8_t r = ps2_tx_poll(d.port);
    if (r != 0) {
      d.since_ms = now;
      d.state = r == 1 ? PS2_INIT_WAIT_BAT : PS2_INIT_RETRY_WAIT;
    }
    break;
  }
  case PS2_INIT_WAIT_BAT:
    if (now - d.since_ms > PS2_BAT_TIMEOUT_MS) {
      d.since_ms = now;
      d.state = PS2_INIT_RETRY_WAIT;
    }
    break;
  case PS2_INIT_SEND_ENABLE:
    d.attempts++;
    ps2_send(d.port, 0xF4);
    d.state = PS2_INIT_SENDING_ENABLE;
    break;
  case PS2_INIT_SENDING_ENABLE: {
    int8_t r = ps2_tx_poll(d.port);
    if (r != 0) {
      d.since_ms = now;
      d.state = r == 1 ? PS2_INIT_WAIT_ENABLE_ACK : PS2_INIT_RETRY_WAIT;
    }
    break;
  }
  case PS2_INIT_WAIT_ENABLE_ACK:
    if (now - d.since_ms > PS2_ACK_TIMEOUT_MS) {
      d.since_ms = now;
      d.state = PS2_INIT_RETRY_WAIT;
    }
    break;
  case PS2_INIT_RETRY_WAIT:
    if (d.connected) {
      d.state = PS2_INIT_DONE; // e.g. a keyboard BAT arrived on its own
    } else if (now - d.since_ms > PS2_RETRY_DELAY_MS) {
      if (d.attempts < PS2_INIT_ATTEMPTS) {
        d.state = PS2_INIT_SEND_RESET;
      } else {
        Serial1.printf("No PS/2 %s\n", d.name);
        d.state = PS2_INIT_DONE;
      }
    }
    break;
  case PS2_INIT_DONE:
    if (d.is_mouse && d.packet_len > 0 &&
        now - d.packet_ms > PS2_PACKET_TIMEOUT_MS) {
      // Incomplete packet. "AA 00" is a mouse that was (re)plugged.
      if (d.packet_len == 2 && d.packet[0] == 0xAA && d.packet[1] == 0x00) {
        Serial1.println("PS/2 mouse plugged");
        ps2_init_restart_enable(d);
      }
      d.packet_len = 0;
    }
    break;
  }
}

// --- keyboard LEDs ---
// LED byte in PS/2 (command 0xED) format.
#define LED_SCROLL 0x01
#define LED_NUM 0x02
#define LED_CAPS 0x04

// What the LEDs should show, as set by the PC with 0xED <value> (like on a
// standard AT, the PC owns the LED state; the keyboard never changes it).
volatile uint8_t led_state = 0;

// PS/2 keyboard: send ED <leds> whenever led_state changes. Runs from loop()
// once the keyboard is initialised; acks (FA) are seen by the byte handler.
enum Ps2LedState : uint8_t {
  PS2_LED_IDLE,
  PS2_LED_SENDING_CMD,
  PS2_LED_WAIT_CMD_ACK,
  PS2_LED_SENDING_VALUE,
  PS2_LED_WAIT_VALUE_ACK,
};

uint8_t ps2_led_state = PS2_LED_IDLE;
uint8_t ps2_led_sent = 0;    // what the keyboard shows (0 after reset/BAT)
uint8_t ps2_led_pending = 0; // value being sent
uint32_t ps2_led_since_ms = 0;
bool ps2_led_got_ack = false;

static void ps2_led_task(Ps2Device &d) {
  uint32_t now = millis();
  switch (ps2_led_state) {
  case PS2_LED_IDLE:
    if (d.state == PS2_INIT_DONE && d.connected &&
        ps2_led_sent != led_state) {
      ps2_led_pending = led_state;
      ps2_led_got_ack = false;
      ps2_send(d.port, 0xED);
      ps2_led_state = PS2_LED_SENDING_CMD;
    }
    break;
  case PS2_LED_SENDING_CMD:
  case PS2_LED_SENDING_VALUE: {
    int8_t r = ps2_tx_poll(d.port);
    if (r == 1) {
      ps2_led_since_ms = now;
      ps2_led_state = ps2_led_state == PS2_LED_SENDING_CMD
                          ? PS2_LED_WAIT_CMD_ACK
                          : PS2_LED_WAIT_VALUE_ACK;
    } else if (r == -1) {
      Serial1.println("PS/2 keyboard: LED command not sent");
      ps2_led_sent = ps2_led_pending; // don't retry forever
      ps2_led_state = PS2_LED_IDLE;
    }
    break;
  }
  case PS2_LED_WAIT_CMD_ACK:
    if (ps2_led_got_ack) {
      ps2_led_got_ack = false;
      ps2_send(d.port, ps2_led_pending);
      ps2_led_state = PS2_LED_SENDING_VALUE;
    } else if (now - ps2_led_since_ms > PS2_ACK_TIMEOUT_MS) {
      Serial1.println("PS/2 keyboard: no ack for LED command");
      ps2_led_sent = ps2_led_pending;
      ps2_led_state = PS2_LED_IDLE;
    }
    break;
  case PS2_LED_WAIT_VALUE_ACK:
    if (ps2_led_got_ack || now - ps2_led_since_ms > PS2_ACK_TIMEOUT_MS) {
      ps2_led_sent = ps2_led_pending;
      ps2_led_state = PS2_LED_IDLE;
    }
    break;
  }
}

// --- keystroke log (toggle with 'k' on the serial port) ---

bool key_log = true;
static uint8_t key_log_raw[8];
static uint8_t key_log_raw_len = 0;
static uint8_t key_log_out[8];
static uint8_t key_log_out_len = 0;

static void key_log_add(uint8_t *buf, uint8_t &len, uint8_t byte) {
  if (len < 8) {
    buf[len++] = byte;
  }
}

// one line per key event: raw bytes from the device -> set 1 sent to the PC
static void key_log_flush(const char *source) {
  if (key_log && key_log_raw_len) {
    Serial1.printf("%s key:", source);
    for (uint8_t i = 0; i < key_log_raw_len; i++) {
      Serial1.printf(" %02X", key_log_raw[i]);
    }
    Serial1.print(" -> set1:");
    for (uint8_t i = 0; i < key_log_out_len; i++) {
      Serial1.printf(" %02X", key_log_out[i]);
    }
    bool brk = key_log_out_len && (key_log_out[key_log_out_len - 1] & 0x80);
    Serial1.println(brk ? " (break)" : " (make)");
  }
  key_log_raw_len = 0;
  key_log_out_len = 0;
}

static void key_out(uint8_t sc) {
  key_log_add(key_log_out, key_log_out_len, sc);
  data_buf_write(sc, false);
}

// --- keyboard bytes ---

static bool ps2_is_e0 = false;
static bool ps2_is_e1 = false;
static bool ps2_is_f0 = false;

static void process_ps2_scancode(uint8_t byte) {
  key_log_add(key_log_raw, key_log_raw_len, byte);
  if (byte == 0xE0) {
    ps2_is_e0 = true;
    key_out(0xE0);
  } else if (byte == 0xE1) {
    ps2_is_e1 = true;
    key_out(0xE1);
  } else if (byte == 0xF0) {
    ps2_is_f0 = true;
  } else {
    uint8_t sc = scancode2_to_scancode1[byte];
    if (ps2_is_f0) {
      sc |= 0x80;
    }
    key_out(sc);
    key_log_flush("PS/2");

    ps2_is_f0 = false;
    ps2_is_e0 = false;
    ps2_is_e1 = false;
  }
}

static void process_ps2_kbd_byte(Ps2Device &d, uint8_t byte) {
  // Replies to commands (and the power-on BAT) are not scan codes: swallow
  // them instead of handing them to the PC.
  switch (byte) {
  case 0xAA: // BAT passed (after reset or power-on / hot plug)
    d.connected = true;
    ps2_led_sent = 0; // LEDs are off after BAT: send the state again
    ps2_led_state = PS2_LED_IDLE;
    if (d.state != PS2_INIT_DONE) {
      Serial1.println("PS/2 keyboard detected");
      d.state = PS2_INIT_DONE;
    }
    return;
  case 0xFC: // BAT failed
    d.connected = false;
    return;
  case 0xFA: // ack
    ps2_led_got_ack = true;
    return;
  case 0xFE: // resend
    return;
  }
  d.connected = true;
  process_ps2_scancode(byte);
}

// --- mouse bytes ---

static void process_ps2_mouse_byte(Ps2Device &d, uint8_t byte) {
  if (d.state != PS2_INIT_DONE) {
    // During init everything is a reply: FA, AA (BAT), 00 (mouse ID)...
    if (byte == 0xAA) {
      d.bat_seen = true;
    } else if (byte == 0x00 && d.bat_seen) {
      d.bat_seen = false;
      if (d.state != PS2_INIT_SENDING_ENABLE &&
          d.state != PS2_INIT_WAIT_ENABLE_ACK) {
        ps2_init_restart_enable(d);
      }
    } else if (byte == 0xFA && (d.state == PS2_INIT_SENDING_ENABLE ||
                                d.state == PS2_INIT_WAIT_ENABLE_ACK)) {
      d.connected = true;
      Serial1.println("PS/2 mouse detected");
      d.state = PS2_INIT_DONE;
    }
    return;
  }

  // Streaming: standard 3-byte packets, already in the format the PC wants.
  uint32_t now = millis();
  if (d.packet_len > 0 && now - d.packet_ms > PS2_PACKET_TIMEOUT_MS) {
    d.packet_len = 0; // resync
  }
  if (d.packet_len == 0 && !(byte & 0x08)) {
    return; // first byte always has bit 3 set: out of sync, drop
  }
  d.packet[d.packet_len++] = byte;
  d.packet_ms = now;
  if (d.packet_len == 3) {
    d.connected = true;
    data_buf_write(d.packet[0], true);
    data_buf_write(d.packet[1], true);
    data_buf_write(d.packet[2], true);
    d.packet_len = 0;
  }
}

static void ps2_task() {
  ps2_device_task(ps2_kbd);
  ps2_device_task(ps2_mouse);
  ps2_led_task(ps2_kbd);
  while (ps2_has_data(ps2_kbd_port)) {
    process_ps2_kbd_byte(ps2_kbd, ps2_pop(ps2_kbd_port));
  }
  while (ps2_has_data(ps2_mouse_port)) {
    process_ps2_mouse_byte(ps2_mouse, ps2_pop(ps2_mouse_port));
  }
}

bool callback = false;

PIO pio_bus = pio0;
int sm_bus = -1;

uint8_t keyboard_addr = 0;
uint8_t keyboard_instance = 0;
uint8_t usb_led_sent = 0xFF; // LED state last sent to the USB keyboard
uint8_t mouse_addr = 0;

volatile uint32_t command_write = 0;
volatile uint32_t status_read = 0;
volatile uint32_t data_read = 0;
volatile uint32_t data_write = 0;
volatile uint8_t write_commands[32] = {0};
volatile uint8_t write_datas[32] = {0};

volatile uint8_t command_byte = 0b01000111;

volatile uint8_t next60h_write = 0;
// byte to return after an 0xFA ack (e.g. mouse ID), one shot
volatile uint8_t after_ack = 0;
volatile bool has_after_ack = false;
volatile bool keyboard_enabled = true;
volatile bool mouse_enabled = false;

// 8042 self test (AAh) received before keyboard detection finished: the
// reply is sent from loop() once we know (the BIOS waits for it).
volatile bool selftest_pending = false;
#define USB_KEYBOARD_GRACE_MS 1000

// Queue of keyboard/mouse bytes waiting behind the output buffer
struct KbdBufferItem {
  uint8_t data;
  bool is_mouse;
};

#define DATA_BUF_SIZE 16
KbdBufferItem data_buffer[DATA_BUF_SIZE];
volatile uint8_t data_head = 0;
volatile uint8_t data_tail = 0;
volatile uint8_t data_count = 0;

// The output buffer: the byte the PC reads next from port 60h.
volatile bool out_full = false;
volatile bool out_from_queue = false; // a device byte, not a command reply
KbdBufferItem out_item;

// core0 (keyboard/mouse/USB) and core1 (bus) both use the queue and the
// output buffer.
static spin_lock_t *out_lock = spin_lock_init(spin_lock_claim_unused(true));

// Status register for the byte latched in the output buffer:
// bit 0 = output buffer full, bit 2 = system flag, bit 5 = byte is from aux.
inline uint8_t status_register(bool full, bool is_mouse) {
  return 0x4 | ((full && is_mouse) << 5) | full;
}

// Latches the byte the PC reads next from port 60h, and drives IRQ1/IRQ12
// like an 8042: high while a byte is waiting (and enabled in the command
// byte). The line drops for a moment between bytes so the edge-triggered
// PIC sees each one. Call with out_lock held.
static void latch_output(uint8_t data, bool full, bool is_mouse,
                         bool from_queue) {
  out_full = full;
  out_from_queue = full && from_queue;
  out_item = {data, is_mouse};

  gpio_put(KEYBOARD_INTERRUPT_PIN, false);
  gpio_put(MOUSE_INTERRUPT_PIN, false);
  pio_sm_put(pio_bus, sm_bus, status_register(full, is_mouse) << 8 | data);
  if (full) {
    busy_wait_us_32(1);
    if (is_mouse) {
      gpio_put(MOUSE_INTERRUPT_PIN, (command_byte & 0b10) != 0);
    } else {
      gpio_put(KEYBOARD_INTERRUPT_PIN, (command_byte & 0b01) != 0);
    }
  }
}

static bool queue_pop(KbdBufferItem &item) {
  if (data_count == 0)
    return false;
  item = data_buffer[data_tail];
  data_tail = (data_tail + 1) % DATA_BUF_SIZE;
  data_count--;
  return true;
}

static void queue_push_front(const KbdBufferItem &item) {
  if (data_count < DATA_BUF_SIZE) {
    data_tail = (data_tail + DATA_BUF_SIZE - 1) % DATA_BUF_SIZE;
    data_buffer[data_tail] = item;
    data_count++;
  }
}

// Latches a reply to a command (always "full", 00h included). A device byte
// that was waiting goes back to the front of the queue instead of being
// overwritten: it is read after the reply.
void set_next_60h_byte(uint8_t data, bool is_mouse = false) {
  uint32_t save = spin_lock_blocking(out_lock);
  if (out_full && out_from_queue) {
    queue_push_front(out_item);
  }
  latch_output(data, true, is_mouse, false);
  spin_unlock(out_lock, save);
}

void set_next_60h_read(uint8_t data, bool is_mouse = false) {
  set_next_60h_byte(data, is_mouse);
}

void setup() {
#ifndef PS2_ONLY
  Serial1.setTX(12);
  Serial1.setRX(13);
#endif

  Serial1.begin(115200);

#ifndef PS2_ONLY
  tuh_hid_mount_cb(0, 0, NULL, 0);
  while (!callback) {
    Serial1.println("Callbacks are not ours");
  }

  if (!USBHost.begin(0)) {
    Serial1.println("Failed to initialize USB Host");
  }; // 0 means use native RP2040 host
#endif
  pinMode(KEYBOARD_INTERRUPT_PIN, OUTPUT);
  digitalWrite(KEYBOARD_INTERRUPT_PIN, LOW);

  pinMode(MOUSE_INTERRUPT_PIN, OUTPUT);
  digitalWrite(MOUSE_INTERRUPT_PIN, LOW);

  pinMode(PS2_KBD_CLK_PIN, INPUT_PULLUP);
  pinMode(PS2_KBD_DATA_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PS2_KBD_CLK_PIN), ps2_kbd_clock_isr,
                  FALLING);

  pinMode(PS2_MOUSE_CLK_PIN, INPUT_PULLUP);
  pinMode(PS2_MOUSE_DATA_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PS2_MOUSE_CLK_PIN),
                  ps2_mouse_clock_isr, FALLING);

  Serial1.println("Started");
}

void setup1() {
  // --- Bus Interface Initialization ---
  // Using PIO0 for the Bus Interface
  // pio_bus is global
  unsigned int offset_bus = pio_add_program(pio_bus, &bus_program);
  sm_bus = pio_claim_unused_sm(pio_bus, true);

  while (sm_bus < 0) {
    Serial1.println("Error: Could not claim State Machine for Bus Interface");
  }

  bus_program_init(pio_bus, sm_bus, offset_bus, 0);

  // set the first value of the bus buffer: empty
  uint32_t save = spin_lock_blocking(out_lock);
  latch_output(0, false, false, false);
  spin_unlock(out_lock, save);
}

// A keyboard/mouse byte for the PC (core0).
void data_buf_write(uint8_t data, bool is_mouse) {

  if (is_mouse && !mouse_enabled) {
    return;
  }

  if (!is_mouse && !keyboard_enabled) {
    return;
  }

  uint32_t save = spin_lock_blocking(out_lock);
  if (!out_full) {
    latch_output(data, true, is_mouse, true);
  } else if (data_count < DATA_BUF_SIZE) {
    data_buffer[data_head] = {data, is_mouse};
    data_head = (data_head + 1) % DATA_BUF_SIZE;
    data_count++;
  }
  spin_unlock(out_lock, save);
}

static bool keyboard_present() {
  return keyboard_addr > 0 || ps2_kbd.connected;
}

// Answers a pending self test once keyboard detection is over (core0).
static void selftest_task() {
  if (!selftest_pending) {
    return;
  }
  bool detecting = ps2_kbd.state != PS2_INIT_DONE;
#ifndef PS2_ONLY
  detecting = detecting || millis() < USB_KEYBOARD_GRACE_MS;
#endif
  if (keyboard_present() || !detecting) {
    selftest_pending = false;
    set_next_60h_byte(keyboard_present() ? 0x55 : 0x00);
  }
}

void process8042_64h_write(uint8_t command) {

  switch (command) {
  case 0x20: // read keyboard command byte
    set_next_60h_read(command_byte);
    break;
  case 0xEE: // diagnostic, return EE
    set_next_60h_read(0xEE);
    break;
  case 0xAA: // self test: 55h when a keyboard is there (BondiXT BIOS uses
             // it as keyboard detection), 00h otherwise
    if (keyboard_present()) {
      set_next_60h_byte(0x55);
    } else {
      selftest_pending = true; // still detecting: answered from loop()
    }
    break;
  case 0xA9: // test mouse, return 0 in data
  case 0xAB: // keyboard test, return 0 in data
    set_next_60h_byte(0);
    break;
  case 0x60: // write keyboard command byte. bit 6 = 0 => enable mouse
  case 0xD4: // write to mouse port
    next60h_write = command;
    break;
  case 0xAD: // disable keyboard
    keyboard_enabled = false;
    // Serial1.println("keyboard disabled");
    break;
  case 0xAE: // enable keyboard
    keyboard_enabled = true;
    // Serial1.println("keyboard enabled");
    break;
  case 0xA7: // disable mouse
    mouse_enabled = false;
    // Serial1.println("mouse disabled");
    break;
  case 0xA8: // enable mouse
    mouse_enabled = true;
    // Serial1.println("mouse enabled");
    break;
  }
}

// The PC read port 60h: latch the next byte, if any (core1).
void process8042_60h_read() {
  uint32_t save = spin_lock_blocking(out_lock);
  KbdBufferItem item;
  if (has_after_ack) {
    has_after_ack = false;
    latch_output(after_ack, true, true, false);
  } else if (queue_pop(item)) {
    latch_output(item.data, true, item.is_mouse, true);
  } else {
    latch_output(0, false, false, false);
  }
  spin_unlock(out_lock, save);
}

void process8042_60h_write(uint8_t value) {

  switch (next60h_write) {
  case 0x60:
    command_byte = value;
    mouse_enabled = !(value & 0b00100000);
    keyboard_enabled = !(value & 0b00010000);
    next60h_write = 0;
    return;
  case 0xCD: // write leds value (internal)
    led_state = value & 0x07;
    set_next_60h_read(0xFA);
    next60h_write = 0;
    return;
  case 0xC3: // set autorepeat (internal)
    // TODO set
    set_next_60h_read(0xFA);
    next60h_write = 0;
    return;
  case 0xC0: // select scancode value (internal)
    set_next_60h_read(0xFA);
    next60h_write = 0;
    return;
  case 0xD5: // mouse command parameter (internal)
    set_next_60h_read(0xFA, true);
    next60h_write = 0;
    return;
  case 0xD4: // write to mouse port: this byte is a mouse command
    next60h_write = 0;
    switch (value) {
    case 0xF2: // get ID: standard mouse, 3-byte packets (USB and PS/2 paths)
      after_ack = 0x00;
      has_after_ack = true;
      break;
    case 0xF3: // set sample rate
    case 0xE8: // set resolution
      next60h_write = 0xD5; // a parameter follows
      break;
    }
    set_next_60h_read(0xFA, true);
    return;
  }

  switch (value) {
  case 0xED: // leds: ack, next byte is the LED value
    next60h_write = 0xCD;
    set_next_60h_read(0xFA);
    break;
  case 0xEE: // diagnostic, return EE
    set_next_60h_read(0xEE);
    break;
  case 0xF0: // select scancode
    set_next_60h_read(0x43);
    break;
  case 0xF3: // set autorepeat: ack, next byte is the rate
    next60h_write = 0xC3;
    set_next_60h_read(0xFA);
    break;
  case 0xF2: // we are "ancient AT keyboard" so we don't send an ID
  case 0xF4: // enable scanning
  case 0xF5: // disable scanning
    set_next_60h_read(0xFA);
    break;
  }
}

static void inline stats() {
  static uint32_t last_print = 0;
  if (millis() - last_print > 1000) {
    Serial1.printf("64r: %05d, 64w: %05d, 60r: %05d, 60w: %05d, K: %d, M: %d, "
                   "PS2 kbd: %s, PS2 mouse: %s, USB kbd: %d, USB mouse: %d\n",
                   status_read, command_write, data_read, data_write,
                   keyboard_enabled, mouse_enabled,
                   ps2_status(ps2_kbd), ps2_status(ps2_mouse), keyboard_addr,
                   mouse_addr);
    for (uint32_t i = 0; i < (command_write & 31); i++) {
      Serial1.printf("64w: 0x%02X\n", write_commands[i]);
    }
    for (uint32_t i = 0; i < (data_write & 31); i++) {
      Serial1.printf("60w: 0x%02X\n", write_datas[i]);
    }
    command_write = 0;
    status_read = 0;
    data_read = 0;
    data_write = 0;
    last_print = millis();
  }
}

#ifndef PS2_ONLY
static void usb_led_task();
#endif

void loop() {
#ifndef PS2_ONLY
  USBHost.task();
  usb_led_task();
#endif
  if (Serial1.available()) {
    int inByte = Serial1.read();
    if (inByte == 'r') {
      reset_usb_boot(0, 0);
    } else if (inByte == 'k') {
      key_log = !key_log;
      Serial1.printf("Key log %s\n", key_log ? "on" : "off");
    }
  }
  ps2_task();
  selftest_task();
  stats();
}

void loop1() {

  uint32_t rxempty_mask = (1u << (PIO_FSTAT_RXEMPTY_LSB + sm_bus));

  for (;;) {
    while ((pio_bus->fstat & rxempty_mask) != 0) {
    }
    uint32_t data = pio_bus->rxf[sm_bus];

    // Format from bus.pio:
    // ISR = [a2 (1) << 9  | Data (8) << 1 | Flag (1)]

    uint8_t value = (data >> 1) & 0xFF;
    uint8_t a2 = ((data >> 9) & 0x1);
    bool write = data & 0x1;
    uint8_t output_data = 0;

    // if (!write) {
    //   Serial1.printf("Bus Message: Data: 0x%08X, A2: 0x%05X, Value: 0x%02X
    //   write: %d\n", data, a2, value, write);
    // }

    if (a2) {
      if (write) {
        process8042_64h_write(value);
        write_commands[command_write & 31] = value;
        command_write++;
      } else {
        status_read++;
      }
    } else {
      if (write) {
        process8042_60h_write(value);
        write_datas[data_write & 31] = value;
        data_write++;
      } else {
        process8042_60h_read();
        data_read++;
      }
    }
  }
}

#ifndef PS2_ONLY

// USB keyboard LEDs (boot protocol output report: Num, Caps, Scroll)
static void usb_led_task() {
  if (!keyboard_addr || usb_led_sent == led_state) {
    return;
  }
  static uint8_t report;
  uint8_t leds = led_state;
  report = ((leds & LED_NUM) ? KEYBOARD_LED_NUMLOCK : 0) |
           ((leds & LED_CAPS) ? KEYBOARD_LED_CAPSLOCK : 0) |
           ((leds & LED_SCROLL) ? KEYBOARD_LED_SCROLLLOCK : 0);
  if (tuh_hid_set_report(keyboard_addr, keyboard_instance, 0,
                         HID_REPORT_TYPE_OUTPUT, &report, sizeof(report))) {
    usb_led_sent = leds;
  }
}

void tuh_mount_cb(uint8_t daddr) {
  Serial1.printf("Device attached, address = %d\r\n", daddr);
}

void tuh_umount_cb(uint8_t daddr) {
  Serial1.printf("Device removed, address = %d\r\n", daddr);
}

#define MAX_REPORT 4

static uint8_t const keycode2ascii[128][2] = {HID_KEYCODE_TO_ASCII};

// Each HID instance can has multiple reports
static struct {
  uint8_t report_count;
  tuh_hid_report_info_t report_info[MAX_REPORT];
} hid_info[CFG_TUH_HID];

static void process_kbd_report(hid_keyboard_report_t const *report);
static void process_mouse_report(hid_mouse_report_t const *report);
static void process_generic_report(uint8_t dev_addr, uint8_t instance,
                                   uint8_t const *report, uint16_t len);

void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t instance,
                      uint8_t const *desc_report, uint16_t desc_len) {
  if (dev_addr == 0) {
    callback = true;
    return;
  }
  Serial1.printf("HID device address = %d, instance = %d is mounted\r\n",
                 dev_addr, instance);

  // Interface protocol (hid_interface_protocol_enum_t)
  const char *protocol_str[] = {"None", "Keyboard", "Mouse"};
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);

  Serial1.printf("HID Interface Protocol = %s\r\n", protocol_str[itf_protocol]);

  if (itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) {
    keyboard_addr = dev_addr;
    keyboard_instance = instance;
    usb_led_sent = 0xFF; // force sending the current state
  } else if (itf_protocol == HID_ITF_PROTOCOL_MOUSE) {
    mouse_addr = dev_addr;
  }

  // By default, host stack will use boot protocol on supported interface.
  // Therefore for this simple example, we only need to parse generic report
  // descriptor (with built-in parser)
  if (itf_protocol == HID_ITF_PROTOCOL_NONE) {
    hid_info[instance].report_count = tuh_hid_parse_report_descriptor(
        hid_info[instance].report_info, MAX_REPORT, desc_report, desc_len);
    Serial1.printf("HID has %u reports \r\n", hid_info[instance].report_count);
  }

  // request to receive report
  // tuh_hid_report_received_cb() will be invoked when report is available
  if (!tuh_hid_receive_report(dev_addr, instance)) {
    Serial1.printf("Error: cannot request to receive report\r\n");
  }
}

// Invoked when device with hid interface is un-mounted
void tuh_hid_umount_cb(uint8_t dev_addr, uint8_t instance) {
  Serial1.printf("HID device address = %d, instance = %d is unmounted\r\n",
                 dev_addr, instance);
  if (dev_addr == keyboard_addr) {
    keyboard_addr = 0;
  } else if (dev_addr == mouse_addr) {
    mouse_addr = 0;
  }
}

// Invoked when received report from device via interrupt endpoint
void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t instance,
                                uint8_t const *report, uint16_t len) {
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);

  switch (itf_protocol) {
  case HID_ITF_PROTOCOL_KEYBOARD:
    process_kbd_report((hid_keyboard_report_t const *)report);
    break;

  case HID_ITF_PROTOCOL_MOUSE:
    process_mouse_report((hid_mouse_report_t const *)report);
    break;

  default:
    // Generic report requires matching ReportID and contents with previous
    // parsed report info
    process_generic_report(dev_addr, instance, report, len);
    break;
  }

  // continue to request to receive report
  if (!tuh_hid_receive_report(dev_addr, instance)) {
    Serial1.printf("Error: cannot request to receive report\r\n");
  }
}

//--------------------------------------------------------------------+
// Keyboard
//--------------------------------------------------------------------+

// look up new key in previous keys
static inline bool find_key_in_report(hid_keyboard_report_t const *report,
                                      uint8_t keycode) {
  for (uint8_t i = 0; i < 6; i++) {
    if (report->keycode[i] == keycode) {
      return true;
    }
  }
  return false;
}

static void send_scancode(uint8_t hid_code, bool make) {
  if (hid_code >= HID_TO_SCANCODE_TABLE_SIZE)
    return;
  uint16_t scan = hid_to_scancode[hid_code];
  if (!scan)
    return;

  key_log_add(key_log_raw, key_log_raw_len, hid_code);
  if (scancode_is_extended(scan)) {
    key_out(0xE0);
  }

  uint8_t base = scancode_base(scan);
  if (make) {
    key_out(base);
  } else {
    key_out(base | 0x80);
  }
  key_log_flush("USB (HID)");

}

static void process_kbd_report(hid_keyboard_report_t const *report) {
  static hid_keyboard_report_t prev_report = {
      0, 0, {0}}; // previous report to check key released

  // Process modifiers
  uint8_t changed_modifiers = report->modifier ^ prev_report.modifier;
  if (changed_modifiers) {
    for (uint8_t i = 0; i < 8; i++) {
      if (changed_modifiers & (1 << i)) {
        // HID modifier codes start at 0xE0
        if (report->modifier & (1 << i)) {
          send_scancode(0xE0 + i, true);
        } else {
          send_scancode(0xE0 + i, false);
        }
      }
    }
  }

  // Check for released keys (present in prev, not in current)
  for (uint8_t i = 0; i < 6; i++) {
    uint8_t code = prev_report.keycode[i];
    if (code) {
      if (!find_key_in_report(report, code)) {
        send_scancode(code, false);
      }
    }
  }

  // Check for pressed keys (present in current, not in prev)
  for (uint8_t i = 0; i < 6; i++) {
    uint8_t code = report->keycode[i];
    if (code) {
      if (!find_key_in_report(&prev_report, code)) {
        send_scancode(code, true);
      }
    }
  }

  prev_report = *report;
}

static void process_mouse_report(hid_mouse_report_t const *report) {

  // Standard PS/2 Mouse Packet (3 bytes)
  // Byte 1: Y ovf, X ovf, Y sign, X sign, 1, M, R, L
  // Byte 2: X
  // Byte 3: Y

  uint8_t buttons = 0;
  if (report->buttons & MOUSE_BUTTON_LEFT)
    buttons |= 1;
  if (report->buttons & MOUSE_BUTTON_RIGHT)
    buttons |= 2;
  if (report->buttons & MOUSE_BUTTON_MIDDLE)
    buttons |= 4;

  // PS/2 Y is up-positive, HID is down-positive.
  int16_t rx = report->x;
  int16_t ry = -report->y;

  uint8_t byte1 = 0x08 | (buttons & 0x07);
  if (rx < 0)
    byte1 |= 0x10;
  if (ry < 0)
    byte1 |= 0x20;
  // Overflow handling omitted for simplicity (HID deltas usually fit)

  data_buf_write(byte1, true);
  data_buf_write((uint8_t)rx, true);
  data_buf_write((uint8_t)ry, true);
}

//--------------------------------------------------------------------+
// Generic Report
//--------------------------------------------------------------------+
static void process_generic_report(uint8_t dev_addr, uint8_t instance,
                                   uint8_t const *report, uint16_t len) {
  (void)dev_addr;
  (void)len;

  uint8_t const rpt_count = hid_info[instance].report_count;
  tuh_hid_report_info_t *rpt_info_arr = hid_info[instance].report_info;
  tuh_hid_report_info_t *rpt_info = NULL;

  if (rpt_count == 1 && rpt_info_arr[0].report_id == 0) {
    // Simple report without report ID as 1st byte
    rpt_info = &rpt_info_arr[0];
  } else {
    // Composite report, 1st byte is report ID, data starts from 2nd byte
    uint8_t const rpt_id = report[0];

    // Find report id in the array
    for (uint8_t i = 0; i < rpt_count; i++) {
      if (rpt_id == rpt_info_arr[i].report_id) {
        rpt_info = &rpt_info_arr[i];
        break;
      }
    }

    report++;
    len--;
  }

  if (!rpt_info) {
    Serial1.printf("Couldn't find report info !\r\n");
    return;
  }

  if (rpt_info->usage_page == HID_USAGE_PAGE_DESKTOP) {
    switch (rpt_info->usage) {
    case HID_USAGE_DESKTOP_KEYBOARD:
      // Assume keyboard follow boot report layout
      process_kbd_report((hid_keyboard_report_t const *)report);
      break;

    case HID_USAGE_DESKTOP_MOUSE:
      // Assume mouse follow boot report layout
      process_mouse_report((hid_mouse_report_t const *)report);
      break;

    default:
      Serial1.printf("report[%u] ", rpt_info->report_id);
      for (uint8_t i = 0; i < len; i++) {
        Serial1.printf("%02X ", report[i]);
      }
      Serial1.printf("\r\n");
      break;
    }
  }
}
#endif