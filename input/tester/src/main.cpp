#include <Arduino.h>

#define CLK() __asm ("nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop; \
    nop; nop; nop; nop; nop; nop; nop; nop;")


char kbd_US [128] =
{
    0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b',   
  '\t', /* <-- Tab */
  'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n',     
    0, /* <-- control key */
  'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`',  0, '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/',   0,
  '*',
    0,  /* Alt */
  ' ',  /* Space bar */
    0,  /* Caps lock */
    0,  /* 59 - F1 key ... > */
    0,   0,   0,   0,   0,   0,   0,   0,
    0,  /* < ... F10 */
    0,  /* 69 - Num lock*/
    0,  /* Scroll Lock */
    0,  /* Home key */
    0,  /* Up Arrow */
    0,  /* Page Up */
  '-',
    0,  /* Left Arrow */
    0,
    0,  /* Right Arrow */
  '+',
    0,  /* 79 - End key*/
    0,  /* Down Arrow */
    0,  /* Page Down */
    0,  /* Insert Key */
    0,  /* Delete Key */
    0,   0,   0,
    0,  /* F11 Key */
    0,  /* F12 Key */
    0,  /* All other keys are undefined */
};


// Bus Pin Definitions (Tester Side)
// These must match the wiring to the PIO device under test
#define PIN_AD0 0
#define PIN_RD  8
#define PIN_WR  9
#define PIN_CS  10
#define PIN_READY 11

void setup_bus_pins() {
    pinMode(PIN_CS, OUTPUT);
    pinMode(PIN_RD, OUTPUT);
    pinMode(PIN_WR, OUTPUT);
    pinMode(PIN_READY, INPUT_PULLUP);
    
    digitalWrite(PIN_CS, HIGH); // Inactive
    digitalWrite(PIN_RD, HIGH); // Inactive
    digitalWrite(PIN_WR, HIGH); // Inactive

    // AD0-AD7 are bidirectional, default to INPUT
    for (int i = 0; i < 8; i++) {
        pinMode(PIN_AD0 + i, INPUT);
    }
}

inline void write_bus(uint8_t val) {
    gpio_put_masked(0xFF, val);
}

inline uint8_t read_bus() {
    return (gpio_get_all() & 0xFF);
}

uint8_t in(uint8_t port) {
    // 1. Output Address
    gpio_set_dir_out_masked(0xFF);
    write_bus(port);
    gpio_put(PIN_RD, false);
    gpio_put(PIN_CS, false);
    CLK();
    gpio_set_dir_in_masked(0xFF);
    CLK(); CLK();
    while(!gpio_get(PIN_READY)) {};
    uint8_t data = read_bus();

    gpio_put(PIN_RD, true);
    gpio_put(PIN_CS, true);
    
    return data;
}

void out(uint8_t port, uint8_t data) {

    // 1. Output Address
    gpio_set_dir_out_masked(0xFF);
    write_bus(port);
    gpio_put(PIN_CS, false);
    
    CLK();

    write_bus(data);
    gpio_put(PIN_WR, false);

    CLK();
    CLK();

    // 6. End Cycle
    gpio_put(PIN_WR, true);
    gpio_put(PIN_CS, true);
    
    // Reset Bus Direction to Input (Safety)
    gpio_set_dir_in_masked(0xFF);
}

bool send_command(uint8_t address, uint8_t cmd) {
    uint16_t timeout = 1000;
    while((in(0x64) & 0b10) && (timeout > 0)) { timeout --; } // wait for input buffer not full
    if (timeout > 0) {
        out(address, cmd);
        return true;
    }
    return false;
}

typedef struct {
    uint8_t data;
    bool mouse;
} ps2data;


uint8_t last_poll = 0;
bool poll_data() {
    return ((last_poll = in(0x64)) & 1);
}

ps2data read_data() {
    return ps2data { in(0x60), (last_poll & 0x20) > 0 };
}

bool send_controller_command(uint8_t cmd) {
    return send_command(0x60, cmd);
}

bool send_mouse_controller_command(uint8_t cmd) {
    if (send_command(0x64, 0xD4)) {
        return send_controller_command(cmd);

    }
    return false;
}

void setup() {
    Serial.begin(115200);
    if (!Serial1.setTX(12)) {
        Serial.println("Failed to set TX");
    }
    if (!Serial1.setRX(13)) {
        Serial.println("Failed to set RX");
    }
    Serial1.begin(115200);

    delay(1000);


    Serial.println("Started");

    setup_bus_pins();

    send_command(0x64, 0xA8); // enable mouse

}

void loop1() {
    if (Serial1.available()) {
        int inByte = Serial1.read();
        Serial.write(inByte);
    }
    if (Serial.available()) {
        int inByte = Serial.read();
        Serial.write(inByte);
        Serial1.write(inByte);
    }
}

void loop() {
    static uint8_t mouse[3] = {0};
    static uint8_t mouse_idx = 0;
    if(poll_data()) {
        ps2data data = read_data();
        if (!data.mouse) {
            uint8_t ascii = kbd_US[data.data - (data.data < 128 ? 0 : 128)] ; 
            Serial.printf("0x%x '%c' %s\n", data.data, ascii, data.data < 128 ? "dn" : "up");
        } else {
            mouse[mouse_idx++] = data.data;
            if (mouse_idx == 3) {
                mouse_idx = 0;
                int8_t x = (int8_t)mouse[1];
                int8_t y = (int8_t)mouse[2];
                bool left = mouse[0] & 0x01;
                bool right = mouse[0] & 0x02;
                bool middle = mouse[0] & 0x04;
                Serial.printf("Mouse: L:%d R:%d M:%d X:%d Y:%d\n", left, right, middle, x, y);
            }
        }
    }
}

