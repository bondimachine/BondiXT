#include <Arduino.h>
#include <Adafruit_TinyUSB.h>

#if not(CFG_TUD_HID)
  #error "No HID support"
#endif

Adafruit_USBH_Host USBHost;

bool callback = false;
void setup() {
    Serial1.setTX(12);
    Serial1.setRX(13);
    Serial1.begin(115200);

    tuh_hid_mount_cb(0, 0, NULL, 0);
    while(!callback) {
      Serial1.println("Callbacks are not ours");
    }

    if(!USBHost.begin(0)) {
      Serial1.println("Failed to initialize USB Host");
    }; // 0 means use native RP2040 host

    Serial1.println("Started");
}

void loop() {
    USBHost.task();
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

static void process_kbd_report(hid_keyboard_report_t const *report) {
  static hid_keyboard_report_t prev_report = {0, 0, {0}};// previous report to check key released

  //------------- example code ignore control (non-printable) key affects -------------//
  for (uint8_t i = 0; i < 6; i++) {
    if (report->keycode[i]) {
      if (find_key_in_report(&prev_report, report->keycode[i])) {
        // exist in previous report means the current key is holding
      } else {
        // not existed in previous report means the current key is pressed
        bool const is_shift = report->modifier & (KEYBOARD_MODIFIER_LEFTSHIFT | KEYBOARD_MODIFIER_RIGHTSHIFT);
        uint8_t ch = keycode2ascii[report->keycode[i]][is_shift ? 1 : 0];
        Serial1.write(ch);
        if (ch == '\r') {
          Serial1.write('\n');
        }

        Serial1.flush();
      }
    }
    // TODO example skips key released
  }

  prev_report = *report;
}

static void process_mouse_report(hid_mouse_report_t const *report) {
  static hid_mouse_report_t prev_report = {0};

  // button state
  // uint8_t button_changed_mask = report->buttons ^ prev_report.buttons;
  // if (button_changed_mask & report->buttons) { 
  // }

    Serial1.printf("Mouse %c%c%c (%d, %d, %)d\r\n", 
            report->buttons & MOUSE_BUTTON_LEFT ? 'L' : '-',
           report->buttons & MOUSE_BUTTON_MIDDLE ? 'M' : '-',
           report->buttons & MOUSE_BUTTON_RIGHT ? 'R' : '-',
                   report->x, report->y, report->wheel);
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
    Serial.printf("Couldn't find report info !\r\n");
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
        Serial.printf("report[%u] ", rpt_info->report_id);
        for (uint8_t i = 0; i < len; i++) {
          Serial.printf("%02X ", report[i]);
        }
        Serial.printf("\r\n");
        break;
    }
  }
}