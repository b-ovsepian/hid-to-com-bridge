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

AUTO_DEV=""
if [[ -d /dev/input/by-id ]]; then
    shopt -s nullglob
    for kbd_link in /dev/input/by-id/*-event-kbd; do
        AUTO_DEV="$kbd_link"
        echo "Auto-detected scanner candidate: $kbd_link -> $(readlink -f "$kbd_link")"
        break
    done
    shopt -u nullglob
fi

# Keep the stable by-id link, NOT the eventN it points to now: eventN changes between boots
# and after a re-plug (another input device can take the number), and the bridge then reads
# the wrong device silently.
read -rp "Enter scanner device (default: ${AUTO_DEV:-auto-detect at every start}): " DEV_INPUT
SCANNER_DEVICE="${DEV_INPUT:-$AUTO_DEV}"
[[ -n "$SCANNER_DEVICE" && "$SCANNER_DEVICE" != /* ]] && SCANNER_DEVICE="/dev/input/$SCANNER_DEVICE"

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
Environment=SCANNER_DEVICE=$SCANNER_DEVICE
ExecStart=/usr/bin/python3 $SCRIPT_DEST
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
systemctl start hid-com-bridge

# ── result ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup complete ==="
systemctl status hid-com-bridge --no-pager || true
echo ""
echo "Virtual port: /dev/ttyQR0"
echo "Test with:    cat /dev/ttyQR0"
echo "Logs:         journalctl -u hid-com-bridge -f"
