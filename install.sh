#!/usr/bin/env bash
set -euo pipefail
APP_DIR=/opt/motiprint
RUN_USER=${RUN_USER:-pi}
VENV_DIR="${APP_DIR}/venv"

echo "Installing Motiprint into $APP_DIR"

if [ ""$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# Ensure current directory contains project (app/ + motiprint.py)
if [ ! -d "./app" ] || [ ! -f "./motiprint.py" ]; then
  echo "Please run this installer from the motiprint project root (where motiprint.py and app/ live)."
  exit 1
fi

# Clean target and copy project files
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
rsync -a . "$APP_DIR/"

chown -R "$RUN_USER":"$RUN_USER" "$APP_DIR"

echo "Installing system packages..."
apt update
apt install -y python3 python3-venv python3-pip cups libcairo2 libpango-1.0-0 libgdk-pixbuf2.0-0 libffi-dev build-essential git lp-solve imagemagick jp2a

# Create venv and install python packages
sudo -u "$RUN_USER" python3 -m venv "$VENV_DIR"
sudo -u "$RUN_USER" "$VENV_DIR/bin/pip" install --upgrade pip
if [ -f "$APP_DIR/requirements.txt" ]; then
  sudo -u "$RUN_USER" "$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"
else
  sudo -u "$RUN_USER" "$VENV_DIR/bin/pip" install jinja2 qrcode weasyprint pycups flask sqlalchemy pyyaml requests python-dateutil
fi

# Create necessary folders
mkdir -p "$APP_DIR/logs" "$APP_DIR/data" "$APP_DIR/qr"
chown -R "$RUN_USER":"$RUN_USER" "$APP_DIR"

# Setup systemd service
SERVICE_FILE=/etc/systemd/system/motiprint.service
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Motiprint Daily Motivation Service
After=network-online.target cups.service
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/motiprint
ExecStart=/opt/motiprint/venv/bin/python /opt/motiprint/motiprint.py
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# udev rule (narrow this rule down to your printer by idVendor/idProduct)
UDEV_RULE=/etc/udev/rules.d/99-motiprint-printer.rules
cat > "$UDEV_RULE" <<'EOF'
# Restart motiprint when the specific USB printer is added (replace 1234/abcd)
# Find ids with: lsusb -> Bus 001 Device 004: ID 1234:abcd Manufacturer Model
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="1234", ATTRS{idProduct}=="abcd", RUN+="/bin/systemctl restart motiprint.service"
EOF

systemctl daemon-reload
systemctl enable --now motiprint.service
udevadm control --reload

echo "Installation finished. Use: sudo journalctl -u motiprint -f to watch logs
