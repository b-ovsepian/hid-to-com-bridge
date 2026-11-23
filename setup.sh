#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/hid-to-com-bridge.py"
SCRIPT_DEST="/usr/local/bin/hid-to-com-bridge.py"
SERVICE_FILE="/etc/systemd/system/hid-com-bridge.service"

# ── must run as root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

# ── dependencies ──────────────────────────────────────────────────────────────
echo "[1/5] Installing python3-evdev..."
apt-get update -qq
apt-get install -y -qq python3-evdev

# ── detect scanner event device ───────────────────────────────────────────────
echo ""
echo "[2/5] Detecting HID input devices..."
echo ""
cat /proc/bus/input/devices | grep -A5 "EV=.*120013\|Kbd" | grep -E "Name|Handlers" || true
echo ""

shopt -s nullglob
CANDIDATES=(/dev/input/by-id/*-event-kbd)
shopt -u nullglob
for c in "${CANDIDATES[@]}"; do echo "  candidate: $c -> $(readlink -f "$c")"; done
AUTO_DEV=""
# only one keyboard-like device -> default to it; several -> the admin must choose (a USB keyboard
# plugged in during setup would otherwise be pinned instead of the scanner)
[[ ${#CANDIDATES[@]} -eq 1 ]] && AUTO_DEV="${CANDIDATES[0]}"

# Keep the stable by-id link, NOT the eventN it points to now: eventN changes between boots
# and after a re-plug (another input device can take the number), and the bridge then reads
# the wrong device silently.
read -rp "Enter scanner device (default: ${AUTO_DEV:-none, choose one above}): " DEV_INPUT || true
SCANNER_DEVICE="${DEV_INPUT:-$AUTO_DEV}"
case "$SCANNER_DEVICE" in
    "" | /*) ;;
    usb-* | platform-* | pci-*) SCANNER_DEVICE="/dev/input/by-id/$SCANNER_DEVICE" ;;
    *) SCANNER_DEVICE="/dev/input/$SCANNER_DEVICE" ;;
esac
case "$SCANNER_DEVICE" in /dev/input/event*) echo "WARNING: $SCANNER_DEVICE is not stable across reboots, prefer /dev/input/by-id/..." ;; esac
if [[ -z "$SCANNER_DEVICE" && ${#CANDIDATES[@]} -gt 1 ]]; then
    echo "ERROR: several keyboard devices found, run again and choose the scanner"; exit 1
fi

if [[ -n "$SCANNER_DEVICE" && ! -e "$SCANNER_DEVICE" ]]; then
    echo "WARNING: $SCANNER_DEVICE does not exist. Change it later: SCANNER_DEVICE in $SERVICE_FILE"
fi

# ── deploy bridge script ──────────────────────────────────────────────────────
echo "[3/5] Installing bridge script to $SCRIPT_DEST..."

if [[ ! -f "$SCRIPT_SRC" ]]; then
    echo "ERROR: hid-to-com-bridge.py not found at $SCRIPT_SRC"
    echo "Place hid-to-com-bridge.py in the same directory as this setup script."
    exit 1
fi

cp "$SCRIPT_SRC" "$SCRIPT_DEST"
# normalize potential Windows line endings to avoid shebang issues under systemd
sed -i 's/\r$//' "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

# ── create systemd service ────────────────────────────────────────────────────
echo "[4/5] Creating systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=HID to COM Bridge
After=multi-user.target

[Service]
Environment="SCANNER_DEVICE=$SCANNER_DEVICE"
ExecStart=/usr/bin/python3 $SCRIPT_DEST
ExecStopPost=/bin/rm -f /dev/ttyQR0
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# ── enable and start ──────────────────────────────────────────────────────────
echo "[5/5] Enabling and starting hid-com-bridge service..."
systemctl daemon-reload
systemctl enable hid-com-bridge
systemctl restart hid-com-bridge   # restart: a re-run must load the new script and unit

# ── result ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup complete ==="
systemctl status hid-com-bridge --no-pager || true
echo ""
echo "Virtual port: /dev/ttyQR0"
echo "Test with:    cat /dev/ttyQR0"
echo "Logs:         journalctl -u hid-com-bridge -f"
