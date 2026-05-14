#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="rootchat-relay"

echo
echo "  ROOT CHAT relay — setup"
echo "  directory: $SCRIPT_DIR"
echo

# System deps
sudo apt-get update -q
sudo apt-get install -y python3-venv python3-pip

# Venv + dependencies
python3 -m venv "$SCRIPT_DIR/venv"
"$SCRIPT_DIR/venv/bin/pip" install --upgrade pip -q
"$SCRIPT_DIR/venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q

echo "  dependencies installed."
echo

# Write and install systemd service
cat > /tmp/$SERVICE_NAME.service <<EOF
[Unit]
Description=Root Chat Relay Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/venv/bin/uvicorn relay:app --host 127.0.0.1 --port 7332
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/$SERVICE_NAME.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "  service installed and started."
echo
echo "  status:  sudo systemctl status $SERVICE_NAME"
echo "  logs:    sudo journalctl -u $SERVICE_NAME -f"
echo "  restart: sudo systemctl restart $SERVICE_NAME"
echo
