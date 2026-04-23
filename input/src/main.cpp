#include <Arduino.h>
#include "hid_to_scancode.h"

#ifndef SIMULATE

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
; Pins 0-7: D0-D7 (Base+0 to Base+7)
; Pin 8: /CS (Base+8) (!A9 & !A8 & !A7 & A6 & A5 & !A4 & !A0 & IO & !ALE) (60 - 6F excluding 61)
; Pin 9: \WR & \RD (Base+9)
; Pin 10: DT/R (Base+10)
; Pin 11: READY
; Pin 12: CLK
; Pin 13: A2
; Pin 26: Keyboard Interrupt
; Pin 27: Mouse Interrupt

*/
bool callback = false;

PIO pio_bus = pio0;
int sm_bus = -1;
uint8_t keyboard_addr = 0;
uint8_t mouse_addr = 0;

volatile uint32_t command_write = 0;
volatile uint32_t status_read = 0;
volatile uint32_t data_read = 0;
volatile uint32_t data_write = 0;
volatile uint8_t write_commands[32] = {0};
volatile uint8_t write_datas[32] = {0};

void setup() {
#ifndef SIMULATE  
    Serial1.setTX(12);
    Serial1.setRX(13);
#endif

    Serial1.begin(115200);

#ifndef SIMULATE  
    tuh_hid_mount_cb(0, 0, NULL, 0);
    while(!callback) {
      Serial1.println("Callbacks are not ours");
    }

    if(!USBHost.begin(0)) {
      Serial1.println("Failed to initialize USB Host");
    }; // 0 means use native RP2040 host
#endif
    pinMode(26, OUTPUT);
    digitalWrite(26, LOW);

    pinMode(27, OUTPUT);
    digitalWrite(27, LOW);

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

}

volatile uint8_t command_byte = 0b01000111;

volatile uint8_t next60h = 0;
volatile uint8_t after_ack = 0;
volatile bool keyboard_enabled = true;
volatile bool mouse_enabled = false;


// Circular buffer for keyboard/mouse data
struct KbdBufferItem {
  uint8_t data;
  bool is_mouse;
};

#define DATA_BUF_SIZE 16
KbdBufferItem data_buffer[DATA_BUF_SIZE];
volatile uint8_t data_head = 0;
volatile uint8_t data_tail = 0;
volatile uint8_t data_count = 0;

void data_buf_write(uint8_t data, bool is_mouse) {

  if (is_mouse && !mouse_enabled) {
    return;
  }

  if (!is_mouse && !keyboard_enabled) {
    return;
  }

  if (data_count < DATA_BUF_SIZE) {
    data_buffer[data_head] = {data, is_mouse};
    data_head = (data_head + 1) % DATA_BUF_SIZE;
    data_count++;
  }

  if (is_mouse && (command_byte & 0b10)) {
    // Mouse Interupt
    gpio_put(27 , true);
    // at least 100 ns
    __asm("nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop;");
    gpio_put(27, false);
  } else if (!is_mouse && (command_byte & 0b1)) {
    // Keyboard Interrupt
    gpio_put(26, true);
    __asm("nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop; nop;");
    gpio_put(26, false);
  }
}

uint8_t data_buf_read() {
  if (data_count == 0) return 0;
  uint8_t data = data_buffer[data_tail].data;
  data_tail = (data_tail + 1) % DATA_BUF_SIZE;
  data_count--;
  return data;
}

void process8042_64h_write(uint8_t command) {

  switch (command) {
    case 0x20: // read keyboard command byte
    case 0x60: // write keyboard command byte. bit 6 = 0 => enable mouse
    case 0xEE: // diagnostic, return EE
    case 0xA9: // test mouse, return 0 in data
    case 0xAA: // test, return 55h in data
    case 0xAB: // keyboard test, return 0 in data
    case 0xD4: // write to mouse port
      next60h = command;
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

uint8_t process8042_60h_read() {
  switch (next60h) {
    case 0: {// read data byte
      uint8_t data = data_buf_read();
      return data;
    }  
    case 0x20: // read keyboard command byte
      next60h = 0;
      return command_byte;
    case 0xA9: // test mouse, return 0 in data
    case 0xAB: // keyboard test, return 0 in data
      next60h = 0;
      return 0;
    case 0xAA: // test, return 55h in data
      next60h = 0;      
      return keyboard_addr > 0 ? 0x55 : 0;
    case 0xEE: // diagnostic, return EE
      next60h = 0;
      return 0xEE;
    case 0xC0: // get scancode (internal)
      next60h = 0;
      return 0x43;
    case 0xF2: // mouse id
      return 0x03;
    case 0xFA: // ack
      next60h = after_ack;
      return 0xFA;
  }
  return 0;
}

void process8042_60h_write(uint8_t value) {

  switch (next60h) {
    case 0x60:
      command_byte = value;
      mouse_enabled = !(value & 0b00100000);
      keyboard_enabled = !(value & 0b00010000);
      next60h = 0xFA;
      return;
    case 0xCD: // write leds value (internal)
      // TODO set the leds
      next60h = 0xFA;
      return;
    case 0xC3: // set autorepeat (internal)
      // TODO set 
      next60h = 0xFA;
      return;
    case 0xC0: // select scancode value (internal)
      next60h = 0xFA;
      return;
    // case 0xD4: // write to mouse port, only care for id, see below.
  }

  switch (value) {
    case 0xED: // leds
      next60h = 0xCD;
      break;
    case 0xEE: // diagnostic, return EE
      next60h = 0xEE;
      break;
    case 0xF0: // select scancode
      next60h = 0xC0;
      break;
    case 0xF3: // set autorepeat;
      next60h = 0xC3;
      break;
    case 0xF2:
      if (next60h == 0xD4) {
        after_ack = 0xF2;
      } else {
        // we are "ancient AT keyboard" so we don't respond anything
        after_ack = 0;
      }
      next60h = 0xFA;
      break;
    case 0xF4: // enable scanning
      next60h = 0xFA;
      break;      
    case 0xF5: // disable scanning
      next60h = 0xFA;
      break;      
  }
}

inline uint8_t status_register() {
  bool has_data = data_count > 0;
  return 0x4 | ((has_data && data_buffer[data_tail].is_mouse) << 5) | (has_data || next60h > 0);
}

#ifndef SIMULATE
void loop() {
    static uint32_t last_print = 0;
    USBHost.task();
    if (Serial1.available()) {
        int inByte = Serial1.read();
        if (inByte == 'r') {
          reset_usb_boot(0,0);
        }
    }
    if (millis() - last_print > 1000) {
      Serial1.printf("64r: %05d, 64w: %05d, 60r: %05d, 60w: %05d, K: %d, M: %d\n", status_read, command_write, data_read, data_write, keyboard_enabled, mouse_enabled);
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
#else

void loop() {
    if (Serial1.available()) {
        int inByte = Serial1.read();
        uint8_t base = ascii2scancode(inByte);
        data_buf_write(base, false);
        data_buf_write(base | 0x80, false);
        Serial1.printf("Simulated key press: %c (0x%02X)\n", inByte, base);
    }
}

#endif

void loop1() {
    uint32_t data = pio_sm_get_blocking(pio_bus, sm_bus);

    // Format from bus.pio:
    // ISR = [a2 (1) << 9  | Data (8) << 1 | Flag (1)]

    uint8_t value = (data >> 1) & 0xFF;
    uint8_t a2 = ((data >> 9) & 0x1);
    bool write = data & 0x1;
    uint8_t output_data = 0;

    if (write) {
      // Serial1.printf("Bus Message: Data: 0x%08X, A2: 0x%05X, Value: 0x%02X write: %d\n", data, a2, value, write);
    }

    if (a2) {
      if (write) {
        write_commands[command_write & 31] = value;
        command_write++;
        process8042_64h_write(value);
      } else {
        status_read++;
        output_data = status_register();
      }
    } else {
      if (write) {
        write_datas[data_write & 31] = value;
        data_write++;
        process8042_60h_write(value);
      } else {
        data_read++;
        output_data = process8042_60h_read();
      }
    }

    if (!write) {
      // Serial1.printf("Bus Message: Data: 0x%08X, A2: 0x%05X, Value: 0x%02X write: %d\n", data, a2, output_data, write);
      pio_sm_put(pio_bus, sm_bus, output_data);
    }

}

#ifndef SIMULATE

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
static void process_generic_report(uint8_t dev_addr, uint8_t instance, uint8_t const *report, uint16_t len);


void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* desc_report, uint16_t desc_len) {
  if (dev_addr == 0) {
    callback = true;
    return;
  }
  Serial1.printf("HID device address = %d, instance = %d is mounted\r\n", dev_addr, instance);

  // Interface protocol (hid_interface_protocol_enum_t)
  const char *protocol_str[] = {"None", "Keyboard", "Mouse"};
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);

  Serial1.printf("HID Interface Protocol = %s\r\n", protocol_str[itf_protocol]);

  if (itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) {
    keyboard_addr = dev_addr;
  } else if (itf_protocol == HID_ITF_PROTOCOL_MOUSE) {
    mouse_addr = dev_addr;
  }

  // By default, host stack will use boot protocol on supported interface.
  // Therefore for this simple example, we only need to parse generic report descriptor (with built-in parser)
  if (itf_protocol == HID_ITF_PROTOCOL_NONE) {
    hid_info[instance].report_count = tuh_hid_parse_report_descriptor(hid_info[instance].report_info, MAX_REPORT, desc_report, desc_len);
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
  Serial1.printf("HID device address = %d, instance = %d is unmounted\r\n", dev_addr, instance);
  if (dev_addr == keyboard_addr) {
    keyboard_addr = 0;
  } else if (dev_addr == mouse_addr) {
    mouse_addr = 0;
  }
}

// Invoked when received report from device via interrupt endpoint
void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t instance, uint8_t const *report, uint16_t len) {
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);

  switch (itf_protocol) {
    case HID_ITF_PROTOCOL_KEYBOARD:
      process_kbd_report((hid_keyboard_report_t const *) report);
      break;

    case HID_ITF_PROTOCOL_MOUSE:
      process_mouse_report((hid_mouse_report_t const *) report);
      break;

    default:
      // Generic report requires matching ReportID and contents with previous parsed report info
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
static inline bool find_key_in_report(hid_keyboard_report_t const *report, uint8_t keycode) {
  for (uint8_t i = 0; i < 6; i++) {
    if (report->keycode[i] == keycode) {
      return true;
    }
  }
  return false;
}

static void send_scancode(uint8_t hid_code, bool make) {
  if (hid_code >= HID_TO_SCANCODE_TABLE_SIZE) return;
  uint16_t scan = hid_to_scancode[hid_code];
  if (!scan) return;
  
  if (scancode_is_extended(scan)) {
    data_buf_write(0xE0, false);
  }
  
  uint8_t base = scancode_base(scan);
  if (make) {
    data_buf_write(base, false);
  } else {
    data_buf_write(base | 0x80, false);
  }
}

static void process_kbd_report(hid_keyboard_report_t const *report) {
  static hid_keyboard_report_t prev_report = {0, 0, {0}};// previous report to check key released

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
  if (report->buttons & MOUSE_BUTTON_LEFT) buttons |= 1;
  if (report->buttons & MOUSE_BUTTON_RIGHT) buttons |= 2;
  if (report->buttons & MOUSE_BUTTON_MIDDLE) buttons |= 4;

  // PS/2 Y is up-positive, HID is down-positive.
  int16_t rx = report->x;
  int16_t ry = -report->y; 
  
  uint8_t byte1 = 0x08 | (buttons & 0x07);
  if (rx < 0) byte1 |= 0x10;
  if (ry < 0) byte1 |= 0x20;
  // Overflow handling omitted for simplicity (HID deltas usually fit)

  data_buf_write(byte1, true);
  data_buf_write((uint8_t)rx, true);
  data_buf_write((uint8_t)ry, true);
}

//--------------------------------------------------------------------+
// Generic Report
//--------------------------------------------------------------------+
static void process_generic_report(uint8_t dev_addr, uint8_t instance, uint8_t const *report, uint16_t len) {
  (void) dev_addr;
  (void) len;

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
        process_kbd_report((hid_keyboard_report_t const *) report);
        break;

      case HID_USAGE_DESKTOP_MOUSE:
        // Assume mouse follow boot report layout
        process_mouse_report((hid_mouse_report_t const *) report);
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