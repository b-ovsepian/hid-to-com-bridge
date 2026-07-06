#!/usr/bin/env python3

import os
import pty
from evdev import InputDevice, ecodes, categorize

scanner = InputDevice("/dev/input/event1")

# create REAL kernel PTY
master_fd, slave_fd = pty.openpty()

tty_name = os.ttyname(slave_fd)

# create stable COM alias
try:
    os.remove("/dev/ttyQR0")
except:
    pass

os.symlink(tty_name, "/dev/ttyQR0")

print("COM PORT READY:", tty_name, "-> /dev/ttyQR0")

buffer = ""
shift = False

keymap = {
    'KEY_A': 'a', 'KEY_B': 'b', 'KEY_C': 'c', 'KEY_D': 'd', 'KEY_E': 'e',
    'KEY_F': 'f', 'KEY_G': 'g', 'KEY_H': 'h', 'KEY_I': 'i', 'KEY_J': 'j',
    'KEY_K': 'k', 'KEY_L': 'l', 'KEY_M': 'm', 'KEY_N': 'n', 'KEY_O': 'o',
    'KEY_P': 'p', 'KEY_Q': 'q', 'KEY_R': 'r', 'KEY_S': 's', 'KEY_T': 't',
    'KEY_U': 'u', 'KEY_V': 'v', 'KEY_W': 'w', 'KEY_X': 'x', 'KEY_Y': 'y',
    'KEY_Z': 'z',

    'KEY_0': '0', 'KEY_1': '1', 'KEY_2': '2', 'KEY_3': '3', 'KEY_4': '4',
    'KEY_5': '5', 'KEY_6': '6', 'KEY_7': '7', 'KEY_8': '8', 'KEY_9': '9',

    'KEY_SLASH': '/',
    'KEY_EQUAL': '=',
    'KEY_MINUS': '-',
    'KEY_KPPLUS': '+',
    'KEY_DOT': '.',
}

for event in scanner.read_loop():

    if event.type != ecodes.EV_KEY:
        continue

    key_event = categorize(event)
    key = key_event.keycode

    # Shift pressed
    if key in ("KEY_LEFTSHIFT", "KEY_RIGHTSHIFT"):
        shift = key_event.keystate == 1
        continue

    # only key down
    if key_event.keystate != 1:
        continue

    if key == "KEY_ENTER":
        os.write(master_fd, (buffer + "\n").encode())
        buffer = ""
        continue

    char = keymap.get(key)

    if not char:
        continue

    if shift:
        if char.isalpha():
            char = char.upper()
        elif char == '=':
            char = '+'

    buffer += char
