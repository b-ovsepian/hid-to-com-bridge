# HID to COM Bridge

Bridges a USB HID keyboard-mode device (barcode/QR scanner, RFID reader, etc.) to a virtual serial port (`/dev/ttyQR0`) so any application can read input via standard COM/TTY interface.

## Architecture

```
HID Scanner (/dev/input/eventX)
        ↓  evdev key events
   Python bridge
        ↓  os.write(master_fd, line + "\n")
   kernel PTY master_fd
        ↓
   slave /dev/pts/X  ←── symlink ── /dev/ttyQR0
        ↓
   Application (opens /dev/ttyQR0 as serial port)
```

## Requirements

- Linux with `systemd`
- Python 3
- `python3-evdev` package
- USB HID scanner (presents as keyboard device)

## Quick Install

```bash
sudo ./setup.sh
```

The installer tries to auto-detect scanner event via `/dev/input/by-id/*-event-kbd` and uses it as default. You can still enter another event manually when prompted.

See [setup.sh](setup.sh) for details.

## Manual Install

### 1. Install dependencies

```bash
sudo apt update
sudo apt install python3-evdev
```

### 2. Find your scanner's event device

```bash
cat /proc/bus/input/devices
# or
sudo evtest
# or (best for USB scanners):
ls -l /dev/input/by-id/
```

Look for your scanner (usually named something like `USB Barcode Scanner`). Note its event node, e.g. `/dev/input/event1`.

Quick verification:

```bash
sudo evtest /dev/input/event1
# scan a code and confirm KEY_* events are printed
```

### 3. Deploy the bridge script

```bash
sudo cp hid-to-com-bridge.py /usr/local/bin/hid-to-com-bridge.py
sudo chmod +x /usr/local/bin/hid-to-com-bridge.py
```

If your device is **not** on `/dev/input/event1`, edit the script:

```bash
sudo nano /usr/local/bin/hid-to-com-bridge.py
# Change: scanner = InputDevice("/dev/input/event1")
```

### 4. Create the systemd service

Create `/etc/systemd/system/hid-com-bridge.service`:

```ini
[Unit]
Description=HID to COM Bridge
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/hid-to-com-bridge.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

### 5. Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable hid-com-bridge
sudo systemctl start hid-com-bridge
```

## Verify It Works

```bash
# Check service is running
sudo systemctl status hid-com-bridge

# Check the virtual port exists
ls -l /dev/ttyQR0

# Read output (scan something)
cat /dev/ttyQR0
```

Each scan will output one line terminated with `\n`.

## Usage in Your Application

Open `/dev/ttyQR0` like any serial port. No special baud rate required (it's a PTY, not real UART).

**Python example:**

```python
import serial
ser = serial.Serial('/dev/ttyQR0')
while True:
    line = ser.readline().decode().strip()
    print("Scanned:", line)
```

**Reading raw:**

```bash
cat /dev/ttyQR0
```

## Troubleshooting

| Problem                            | Solution                                                             |
| ---------------------------------- | -------------------------------------------------------------------- |
| `/dev/ttyQR0` does not exist       | Check `journalctl -u hid-com-bridge -f` for errors                   |
| No output on scan                  | Wrong event device — run `evtest` to find correct one                |
| Permission denied on `/dev/ttyQR0` | Add your user to `dialout` group: `sudo usermod -aG dialout $USER`   |
| Service fails to start             | Check Python and evdev: `python3 -c "from evdev import InputDevice"` |

If you see `python3\r: No such file or directory`, convert line endings:

```bash
sudo sed -i 's/\r$//' /usr/local/bin/hid-to-com-bridge.py
sudo systemctl restart hid-com-bridge
```

## Logs

```bash
journalctl -u hid-com-bridge -f
```

## Uninstall

```bash
sudo systemctl stop hid-com-bridge
sudo systemctl disable hid-com-bridge
sudo rm /etc/systemd/system/hid-com-bridge.service
sudo rm /usr/local/bin/hid-to-com-bridge.py
sudo rm -f /dev/ttyQR0
sudo systemctl daemon-reload
```
