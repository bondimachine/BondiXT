/**
 * HID Keycode to PC AT Scan Code Set 1 (XT scancode) translation table.
 *
 * For standard keys: the value is the single-byte make code.
 * For extended keys (arrow keys, Insert/Delete/Home/End/PgUp/PgDn,
 *   right Ctrl, right Alt, keypad Enter, keypad /, GUI, Apps, Print Screen):
 *   the high byte is 0xE0 and the low byte is the scan code.
 *   These need to be sent as a two-byte sequence: 0xE0 followed by the code.
 *
 * Break (release) codes are the make code OR'd with 0x80.
 * For extended keys, send 0xE0 followed by (code | 0x80).
 *
 * A value of 0x0000 means no mapping / unmapped key.
 *
 * Uses TinyUSB HID_KEY_* constants as indices.
 */

#ifndef HID_TO_SCANCODE_H
#define HID_TO_SCANCODE_H

#include <stdint.h>

// Marker for extended scancodes (require 0xE0 prefix)
#define SC_EXT(code) (0xE000 | (code))

// The table is indexed by HID keycode (0x00 - 0xE7).
// Values are uint16_t: 0x00XX for standard keys, 0xE0XX for extended keys.
static const uint16_t hid_to_scancode[] = {
  // 0x00: HID_KEY_NONE
  0x0000,
  // 0x01: HID_KEY_ERR_ROLLOVER (error)
  0x0000,
  // 0x02: HID_KEY_POST_FAIL (error)
  0x0000,
  // 0x03: HID_KEY_ERR_UNDEFINED (error)
  0x0000,

  // 0x04 - 0x1D: Letters A-Z
  0x001E,  // 0x04: HID_KEY_A           -> AT scancode 0x1E
  0x0030,  // 0x05: HID_KEY_B           -> AT scancode 0x30
  0x002E,  // 0x06: HID_KEY_C           -> AT scancode 0x2E
  0x0020,  // 0x07: HID_KEY_D           -> AT scancode 0x20
  0x0012,  // 0x08: HID_KEY_E           -> AT scancode 0x12
  0x0021,  // 0x09: HID_KEY_F           -> AT scancode 0x21
  0x0022,  // 0x0A: HID_KEY_G           -> AT scancode 0x22
  0x0023,  // 0x0B: HID_KEY_H           -> AT scancode 0x23
  0x0017,  // 0x0C: HID_KEY_I           -> AT scancode 0x17
  0x0024,  // 0x0D: HID_KEY_J           -> AT scancode 0x24
  0x0025,  // 0x0E: HID_KEY_K           -> AT scancode 0x25
  0x0026,  // 0x0F: HID_KEY_L           -> AT scancode 0x26
  0x0032,  // 0x10: HID_KEY_M           -> AT scancode 0x32
  0x0031,  // 0x11: HID_KEY_N           -> AT scancode 0x31
  0x0018,  // 0x12: HID_KEY_O           -> AT scancode 0x18
  0x0019,  // 0x13: HID_KEY_P           -> AT scancode 0x19
  0x0010,  // 0x14: HID_KEY_Q           -> AT scancode 0x10
  0x0013,  // 0x15: HID_KEY_R           -> AT scancode 0x13
  0x001F,  // 0x16: HID_KEY_S           -> AT scancode 0x1F
  0x0014,  // 0x17: HID_KEY_T           -> AT scancode 0x14
  0x0016,  // 0x18: HID_KEY_U           -> AT scancode 0x16
  0x002F,  // 0x19: HID_KEY_V           -> AT scancode 0x2F
  0x0011,  // 0x1A: HID_KEY_W           -> AT scancode 0x11
  0x002D,  // 0x1B: HID_KEY_X           -> AT scancode 0x2D
  0x0015,  // 0x1C: HID_KEY_Y           -> AT scancode 0x15
  0x002C,  // 0x1D: HID_KEY_Z           -> AT scancode 0x2C

  // 0x1E - 0x27: Digits 1-9, 0
  0x0002,  // 0x1E: HID_KEY_1           -> AT scancode 0x02
  0x0003,  // 0x1F: HID_KEY_2           -> AT scancode 0x03
  0x0004,  // 0x20: HID_KEY_3           -> AT scancode 0x04
  0x0005,  // 0x21: HID_KEY_4           -> AT scancode 0x05
  0x0006,  // 0x22: HID_KEY_5           -> AT scancode 0x06
  0x0007,  // 0x23: HID_KEY_6           -> AT scancode 0x07
  0x0008,  // 0x24: HID_KEY_7           -> AT scancode 0x08
  0x0009,  // 0x25: HID_KEY_8           -> AT scancode 0x09
  0x000A,  // 0x26: HID_KEY_9           -> AT scancode 0x0A
  0x000B,  // 0x27: HID_KEY_0           -> AT scancode 0x0B

  // 0x28 - 0x38: Special keys
  0x001C,  // 0x28: HID_KEY_ENTER       -> AT scancode 0x1C
  0x0001,  // 0x29: HID_KEY_ESCAPE      -> AT scancode 0x01
  0x000E,  // 0x2A: HID_KEY_BACKSPACE   -> AT scancode 0x0E
  0x000F,  // 0x2B: HID_KEY_TAB         -> AT scancode 0x0F
  0x0039,  // 0x2C: HID_KEY_SPACE       -> AT scancode 0x39
  0x000C,  // 0x2D: HID_KEY_MINUS       -> AT scancode 0x0C
  0x000D,  // 0x2E: HID_KEY_EQUAL       -> AT scancode 0x0D
  0x001A,  // 0x2F: HID_KEY_BRACKET_LEFT  -> AT scancode 0x1A
  0x001B,  // 0x30: HID_KEY_BRACKET_RIGHT -> AT scancode 0x1B
  0x002B,  // 0x31: HID_KEY_BACKSLASH   -> AT scancode 0x2B
  0x002B,  // 0x32: HID_KEY_EUROPE_1    -> AT scancode 0x2B (non-US # / ~)
  0x0027,  // 0x33: HID_KEY_SEMICOLON   -> AT scancode 0x27
  0x0028,  // 0x34: HID_KEY_APOSTROPHE  -> AT scancode 0x28
  0x0029,  // 0x35: HID_KEY_GRAVE       -> AT scancode 0x29
  0x0033,  // 0x36: HID_KEY_COMMA       -> AT scancode 0x33
  0x0034,  // 0x37: HID_KEY_PERIOD      -> AT scancode 0x34
  0x0035,  // 0x38: HID_KEY_SLASH       -> AT scancode 0x35

  // 0x39 - 0x45: Caps Lock, F1-F12
  0x003A,  // 0x39: HID_KEY_CAPS_LOCK   -> AT scancode 0x3A
  0x003B,  // 0x3A: HID_KEY_F1          -> AT scancode 0x3B
  0x003C,  // 0x3B: HID_KEY_F2          -> AT scancode 0x3C
  0x003D,  // 0x3C: HID_KEY_F3          -> AT scancode 0x3D
  0x003E,  // 0x3D: HID_KEY_F4          -> AT scancode 0x3E
  0x003F,  // 0x3E: HID_KEY_F5          -> AT scancode 0x3F
  0x0040,  // 0x3F: HID_KEY_F6          -> AT scancode 0x40
  0x0041,  // 0x40: HID_KEY_F7          -> AT scancode 0x41
  0x0042,  // 0x41: HID_KEY_F8          -> AT scancode 0x42
  0x0043,  // 0x42: HID_KEY_F9          -> AT scancode 0x43
  0x0044,  // 0x43: HID_KEY_F10         -> AT scancode 0x44
  0x0057,  // 0x44: HID_KEY_F11         -> AT scancode 0x57
  0x0058,  // 0x45: HID_KEY_F12         -> AT scancode 0x58

  // 0x46 - 0x48: Print Screen, Scroll Lock, Pause
  SC_EXT(0x37),  // 0x46: HID_KEY_PRINT_SCREEN  -> E0 37 (simplified)
  0x0046,        // 0x47: HID_KEY_SCROLL_LOCK    -> AT scancode 0x46
  0x0000,        // 0x48: HID_KEY_PAUSE          -> special sequence (E1 1D 45 E1 9D C5)

  // 0x49 - 0x4E: Insert, Home, Page Up, Delete, End, Page Down (extended keys)
  SC_EXT(0x52),  // 0x49: HID_KEY_INSERT         -> E0 52
  SC_EXT(0x47),  // 0x4A: HID_KEY_HOME           -> E0 47
  SC_EXT(0x49),  // 0x4B: HID_KEY_PAGE_UP        -> E0 49
  SC_EXT(0x53),  // 0x4C: HID_KEY_DELETE         -> E0 53
  SC_EXT(0x4F),  // 0x4D: HID_KEY_END            -> E0 4F
  SC_EXT(0x51),  // 0x4E: HID_KEY_PAGE_DOWN      -> E0 51

  // 0x4F - 0x52: Arrow keys (extended)
  SC_EXT(0x4D),  // 0x4F: HID_KEY_ARROW_RIGHT    -> E0 4D
  SC_EXT(0x4B),  // 0x50: HID_KEY_ARROW_LEFT     -> E0 4B
  SC_EXT(0x50),  // 0x51: HID_KEY_ARROW_DOWN     -> E0 50
  SC_EXT(0x48),  // 0x52: HID_KEY_ARROW_UP       -> E0 48

  // 0x53 - 0x63: Num Lock & Keypad
  0x0045,        // 0x53: HID_KEY_NUM_LOCK        -> AT scancode 0x45
  SC_EXT(0x35),  // 0x54: HID_KEY_KEYPAD_DIVIDE   -> E0 35
  0x0037,        // 0x55: HID_KEY_KEYPAD_MULTIPLY -> AT scancode 0x37
  0x004A,        // 0x56: HID_KEY_KEYPAD_SUBTRACT -> AT scancode 0x4A
  0x004E,        // 0x57: HID_KEY_KEYPAD_ADD      -> AT scancode 0x4E
  SC_EXT(0x1C),  // 0x58: HID_KEY_KEYPAD_ENTER    -> E0 1C
  0x004F,        // 0x59: HID_KEY_KEYPAD_1        -> AT scancode 0x4F
  0x0050,        // 0x5A: HID_KEY_KEYPAD_2        -> AT scancode 0x50
  0x0051,        // 0x5B: HID_KEY_KEYPAD_3        -> AT scancode 0x51
  0x004B,        // 0x5C: HID_KEY_KEYPAD_4        -> AT scancode 0x4B
  0x004C,        // 0x5D: HID_KEY_KEYPAD_5        -> AT scancode 0x4C
  0x004D,        // 0x5E: HID_KEY_KEYPAD_6        -> AT scancode 0x4D
  0x0047,        // 0x5F: HID_KEY_KEYPAD_7        -> AT scancode 0x47
  0x0048,        // 0x60: HID_KEY_KEYPAD_8        -> AT scancode 0x48
  0x0049,        // 0x61: HID_KEY_KEYPAD_9        -> AT scancode 0x49
  0x0052,        // 0x62: HID_KEY_KEYPAD_0        -> AT scancode 0x52
  0x0053,        // 0x63: HID_KEY_KEYPAD_DECIMAL  -> AT scancode 0x53

  // 0x64 - 0x65: Europe 2, Application
  0x0056,        // 0x64: HID_KEY_EUROPE_2         -> AT scancode 0x56 (non-US \ |)
  SC_EXT(0x5D),  // 0x65: HID_KEY_APPLICATION      -> E0 5D (Menu/Apps key)

  // 0x66: Power
  SC_EXT(0x5E),  // 0x66: HID_KEY_POWER            -> E0 5E

  // 0x67: Keypad =
  0x0059,        // 0x67: HID_KEY_KEYPAD_EQUAL     -> AT scancode 0x59 (rare)

  // 0x68 - 0x73: F13-F24 (no standard AT scancode for most of these)
  0x0064,  // 0x68: HID_KEY_F13          -> AT scancode 0x64
  0x0065,  // 0x69: HID_KEY_F14          -> AT scancode 0x65
  0x0066,  // 0x6A: HID_KEY_F15          -> AT scancode 0x66
  0x0067,  // 0x6B: HID_KEY_F16          -> AT scancode 0x67
  0x0068,  // 0x6C: HID_KEY_F17          -> AT scancode 0x68
  0x0069,  // 0x6D: HID_KEY_F18          -> AT scancode 0x69
  0x006A,  // 0x6E: HID_KEY_F19          -> AT scancode 0x6A
  0x006B,  // 0x6F: HID_KEY_F20          -> AT scancode 0x6B
  0x006C,  // 0x70: HID_KEY_F21          -> AT scancode 0x6C
  0x006D,  // 0x71: HID_KEY_F22          -> AT scancode 0x6D
  0x006E,  // 0x72: HID_KEY_F23          -> AT scancode 0x6E
  0x0076,  // 0x73: HID_KEY_F24          -> AT scancode 0x76

  // 0x74 - 0x86: Miscellaneous keys (mostly unmapped on XT)
  0x0000,  // 0x74: HID_KEY_EXECUTE
  0x0000,  // 0x75: HID_KEY_HELP
  0x0000,  // 0x76: HID_KEY_MENU
  0x0000,  // 0x77: HID_KEY_SELECT
  0x0000,  // 0x78: HID_KEY_STOP
  0x0000,  // 0x79: HID_KEY_AGAIN
  0x0000,  // 0x7A: HID_KEY_UNDO
  0x0000,  // 0x7B: HID_KEY_CUT
  0x0000,  // 0x7C: HID_KEY_COPY
  0x0000,  // 0x7D: HID_KEY_PASTE
  0x0000,  // 0x7E: HID_KEY_FIND
  0x0000,  // 0x7F: HID_KEY_MUTE
  0x0000,  // 0x80: HID_KEY_VOLUME_UP
  0x0000,  // 0x81: HID_KEY_VOLUME_DOWN
  0x0000,  // 0x82: HID_KEY_LOCKING_CAPS_LOCK
  0x0000,  // 0x83: HID_KEY_LOCKING_NUM_LOCK
  0x0000,  // 0x84: HID_KEY_LOCKING_SCROLL_LOCK
  0x0000,  // 0x85: HID_KEY_KEYPAD_COMMA
  0x0000,  // 0x86: HID_KEY_KEYPAD_EQUAL_SIGN

  // 0x87 - 0x8F: International / Kanji keys
  0x0000,  // 0x87: HID_KEY_KANJI1 (Intl 1)
  0x0000,  // 0x88: HID_KEY_KANJI2 (Intl 2)
  0x0000,  // 0x89: HID_KEY_KANJI3 (Intl 3)
  0x0000,  // 0x8A: HID_KEY_KANJI4 (Intl 4)
  0x0000,  // 0x8B: HID_KEY_KANJI5 (Intl 5)
  0x0000,  // 0x8C: HID_KEY_KANJI6 (Intl 6)
  0x0000,  // 0x8D: HID_KEY_KANJI7 (Intl 7)
  0x0000,  // 0x8E: HID_KEY_KANJI8 (Intl 8)
  0x0000,  // 0x8F: HID_KEY_KANJI9 (Intl 9)

  // 0x90 - 0x98: Language keys
  0x0000,  // 0x90: HID_KEY_LANG1
  0x0000,  // 0x91: HID_KEY_LANG2
  0x0000,  // 0x92: HID_KEY_LANG3
  0x0000,  // 0x93: HID_KEY_LANG4
  0x0000,  // 0x94: HID_KEY_LANG5
  0x0000,  // 0x95: HID_KEY_LANG6
  0x0000,  // 0x96: HID_KEY_LANG7
  0x0000,  // 0x97: HID_KEY_LANG8
  0x0000,  // 0x98: HID_KEY_LANG9

  // 0x99 - 0xA4: Misc
  0x0000,  // 0x99: HID_KEY_ALTERNATE_ERASE
  0x0000,  // 0x9A: HID_KEY_SYSREQ_ATTENTION
  0x0000,  // 0x9B: HID_KEY_CANCEL
  0x0000,  // 0x9C: HID_KEY_CLEAR
  0x0000,  // 0x9D: HID_KEY_PRIOR
  0x0000,  // 0x9E: HID_KEY_RETURN
  0x0000,  // 0x9F: HID_KEY_SEPARATOR
  0x0000,  // 0xA0: HID_KEY_OUT
  0x0000,  // 0xA1: HID_KEY_OPER
  0x0000,  // 0xA2: HID_KEY_CLEAR_AGAIN
  0x0000,  // 0xA3: HID_KEY_CRSEL_PROPS
  0x0000,  // 0xA4: HID_KEY_EXSEL

  // 0xA5 - 0xDF: Reserved / exotic keypad keys (unmapped)
  0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,  // 0xA5-0xAB
  0x0000, 0x0000, 0x0000, 0x0000,                            // 0xAC-0xAF
  0x0000,  // 0xB0: HID_KEY_KEYPAD_00
  0x0000,  // 0xB1: HID_KEY_KEYPAD_000
  0x0000,  // 0xB2: HID_KEY_THOUSANDS_SEPARATOR
  0x0000,  // 0xB3: HID_KEY_DECIMAL_SEPARATOR
  0x0000,  // 0xB4: HID_KEY_CURRENCY_UNIT
  0x0000,  // 0xB5: HID_KEY_CURRENCY_SUBUNIT
  0x0000,  // 0xB6: HID_KEY_KEYPAD_LEFT_PARENTHESIS
  0x0000,  // 0xB7: HID_KEY_KEYPAD_RIGHT_PARENTHESIS
  0x0000,  // 0xB8: HID_KEY_KEYPAD_LEFT_BRACE
  0x0000,  // 0xB9: HID_KEY_KEYPAD_RIGHT_BRACE
  0x0000,  // 0xBA: HID_KEY_KEYPAD_TAB
  0x0000,  // 0xBB: HID_KEY_KEYPAD_BACKSPACE
  0x0000,  // 0xBC: HID_KEY_KEYPAD_A
  0x0000,  // 0xBD: HID_KEY_KEYPAD_B
  0x0000,  // 0xBE: HID_KEY_KEYPAD_C
  0x0000,  // 0xBF: HID_KEY_KEYPAD_D
  0x0000,  // 0xC0: HID_KEY_KEYPAD_E
  0x0000,  // 0xC1: HID_KEY_KEYPAD_F
  0x0000,  // 0xC2: HID_KEY_KEYPAD_XOR
  0x0000,  // 0xC3: HID_KEY_KEYPAD_CARET
  0x0000,  // 0xC4: HID_KEY_KEYPAD_PERCENT
  0x0000,  // 0xC5: HID_KEY_KEYPAD_LESS_THAN
  0x0000,  // 0xC6: HID_KEY_KEYPAD_GREATER_THAN
  0x0000,  // 0xC7: HID_KEY_KEYPAD_AMPERSAND
  0x0000,  // 0xC8: HID_KEY_KEYPAD_DOUBLE_AMPERSAND
  0x0000,  // 0xC9: HID_KEY_KEYPAD_VERTICAL_BAR
  0x0000,  // 0xCA: HID_KEY_KEYPAD_DOUBLE_VERTICAL_BAR
  0x0000,  // 0xCB: HID_KEY_KEYPAD_COLON
  0x0000,  // 0xCC: HID_KEY_KEYPAD_HASH
  0x0000,  // 0xCD: HID_KEY_KEYPAD_SPACE
  0x0000,  // 0xCE: HID_KEY_KEYPAD_AT
  0x0000,  // 0xCF: HID_KEY_KEYPAD_EXCLAMATION
  0x0000,  // 0xD0: HID_KEY_KEYPAD_MEMORY_STORE
  0x0000,  // 0xD1: HID_KEY_KEYPAD_MEMORY_RECALL
  0x0000,  // 0xD2: HID_KEY_KEYPAD_MEMORY_CLEAR
  0x0000,  // 0xD3: HID_KEY_KEYPAD_MEMORY_ADD
  0x0000,  // 0xD4: HID_KEY_KEYPAD_MEMORY_SUBTRACT
  0x0000,  // 0xD5: HID_KEY_KEYPAD_MEMORY_MULTIPLY
  0x0000,  // 0xD6: HID_KEY_KEYPAD_MEMORY_DIVIDE
  0x0000,  // 0xD7: HID_KEY_KEYPAD_PLUS_MINUS
  0x0000,  // 0xD8: HID_KEY_KEYPAD_CLEAR
  0x0000,  // 0xD9: HID_KEY_KEYPAD_CLEAR_ENTRY
  0x0000,  // 0xDA: HID_KEY_KEYPAD_BINARY
  0x0000,  // 0xDB: HID_KEY_KEYPAD_OCTAL
  0x0000,  // 0xDC: HID_KEY_KEYPAD_DECIMAL_2
  0x0000,  // 0xDD: HID_KEY_KEYPAD_HEXADECIMAL
  0x0000,  // 0xDE: Reserved
  0x0000,  // 0xDF: Reserved

  // 0xE0 - 0xE7: Modifier keys
  0x001D,        // 0xE0: HID_KEY_CONTROL_LEFT    -> AT scancode 0x1D
  0x002A,        // 0xE1: HID_KEY_SHIFT_LEFT      -> AT scancode 0x2A
  0x0038,        // 0xE2: HID_KEY_ALT_LEFT        -> AT scancode 0x38
  SC_EXT(0x5B),  // 0xE3: HID_KEY_GUI_LEFT        -> E0 5B (Left Windows)
  SC_EXT(0x1D),  // 0xE4: HID_KEY_CONTROL_RIGHT   -> E0 1D
  0x0036,        // 0xE5: HID_KEY_SHIFT_RIGHT     -> AT scancode 0x36
  SC_EXT(0x38),  // 0xE6: HID_KEY_ALT_RIGHT       -> E0 38
  SC_EXT(0x5C),  // 0xE7: HID_KEY_GUI_RIGHT       -> E0 5C (Right Windows)
};

#define HID_TO_SCANCODE_TABLE_SIZE (sizeof(hid_to_scancode) / sizeof(hid_to_scancode[0]))

/**
 * Check if a scancode is an extended key (requires 0xE0 prefix).
 */
static inline bool scancode_is_extended(uint16_t sc) {
  return (sc & 0xFF00) == 0xE000;
}

/**
 * Get the base scancode byte (strip the E0 marker if present).
 */
static inline uint8_t scancode_base(uint16_t sc) {
  return (uint8_t)(sc & 0x00FF);
}

#endif // HID_TO_SCANCODE_H
