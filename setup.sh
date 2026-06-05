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

DEFAULT_EVENT="event1"
read -rp "Enter scanner event device (default: ${DEFAULT_EVENT}): " EVENT_INPUT
EVENT="${EVENT_INPUT:-$DEFAULT_EVENT}"
EVENT_PATH="/dev/input/${EVENT}"

if [[ ! -e "$EVENT_PATH" ]]; then
    echo "WARNING: $EVENT_PATH does not exist. You can change it later in $SCRIPT_DEST"
fi

# ── deploy bridge script ──────────────────────────────────────────────────────
echo "[3/5] Installing bridge script to $SCRIPT_DEST..."

if [[ ! -f "$SCRIPT_SRC" ]]; then
    echo "ERROR: hid-to-com-bridge.py not found at $SCRIPT_SRC"
    echo "Place hid-to-com-bridge.py in the same directory as this setup script."
    exit 1
fi

cp "$SCRIPT_SRC" "$SCRIPT_DEST"
# patch event device if user chose a different one
sed -i "s|InputDevice(\"/dev/input/event[^\"]*\")|InputDevice(\"$EVENT_PATH\")|g" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

# ── create systemd service ────────────────────────────────────────────────────
echo "[4/5] Creating systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=HID to COM Bridge
After=multi-user.target

[Service]
ExecStart=$SCRIPT_DEST
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
