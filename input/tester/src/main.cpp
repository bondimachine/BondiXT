#include <Arduino.h>

void setup() {
    Serial.begin(115200);
    if (!Serial1.setTX(16)) {
        Serial.println("Failed to set TX");
    }
    if (!Serial1.setRX(17)) {
        Serial.println("Failed to set RX");
    }
    Serial1.begin(115200);
    Serial.println("Started");
}

void loop() {
    if (Serial1.available()) {
        int inByte = Serial1.read();
        Serial.write(inByte);
    }
}