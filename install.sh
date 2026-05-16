#!/usr/bin/env bash
set -e

REPO="https://github.com/r3pc0n/root_chat.git"
INSTALL_DIR="$HOME/.local/share/rootchat"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/rootchat"

# Check Python 3.10+
if ! command -v python3 &>/dev/null; then
    echo "error: python3 not found — install Python 3.10 or newer first"
    exit 1
fi

PY_VER=$(python3 -c "import sys; print(sys.version_info >= (3, 10))")
if [ "$PY_VER" != "True" ]; then
    echo "error: Python 3.10 or newer is required"
    python3 --version
    exit 1
fi

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "updating rootchat..."
    git -C "$INSTALL_DIR" pull
else
    echo "installing rootchat..."
    git clone "$REPO" "$INSTALL_DIR"
fi

# Create venv + install deps
echo "installing dependencies..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -q --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"

# Create launcher
mkdir -p "$BIN_DIR"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/main.py" "\$@"
EOF
chmod +x "$LAUNCHER"

# Add ~/.local/bin to PATH if not already there
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ] && ! grep -q 'local/bin' "$SHELL_RC"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo "added ~/.local/bin to PATH in $SHELL_RC"
fi

echo ""
echo "  rootchat installed!"
echo ""
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "  start a new terminal (or run: export PATH=\"\$HOME/.local/bin:\$PATH\")"
    echo "  then run: rootchat"
else
    echo "  run: rootchat"
fi
echo ""
