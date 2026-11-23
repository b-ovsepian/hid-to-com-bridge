#!/usr/bin/env python3

import glob
import os
import pty
import sys
from evdev import InputDevice, ecodes, categorize


def find_scanner():
    """Scanner path, resolved at every start.

    /dev/input/eventN numbers depend on enumeration order and change between boots and
    after a re-plug (a board button can take event0), so never hard-code eventN. Use
    SCANNER_DEVICE (set by setup.sh to the stable /dev/input/by-id/...-event-kbd link)
    or, if unset, the first by-id keyboard device.
    """
    path = os.environ.get("SCANNER_DEVICE") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not path:
        found = sorted(glob.glob("/dev/input/by-id/*-event-kbd"))
        path = found[0] if found else ""
    if not path or not os.path.exists(path):
        # exit non-zero: systemd (Restart=always) retries until the scanner shows up
        sys.exit("scanner not found (SCANNER_DEVICE=%r)" % path)
    return path


scanner_path = find_scanner()
scanner = InputDevice(scanner_path)
print("SCANNER:", scanner_path, "->", os.path.realpath(scanner_path), scanner.name, flush=True)

# create REAL kernel PTY
master_fd, slave_fd = pty.openpty()

tty_name = os.ttyname(slave_fd)

# create stable COM alias
try:
    os.remove("/dev/ttyQR0")
except:
    pass

os.symlink(tty_name, "/dev/ttyQR0")

print("COM PORT READY:", tty_name, "-> /dev/ttyQR0", flush=True)

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
