# RootChat

A minimal terminal chat app for direct P2P messaging or relay-based communication. Built with Python and Textual.

## Features

- Push-to-talk style terminal UI — raw, minimal, futuristic
- **Direct mode** — connect peer-to-peer over LAN or Tailscale
- **Relay mode** — connect through a self-hosted relay server (WebSocket)
- **E2E encryption** — automatic in direct mode; password-based in relay mode
- Usernames, chat history saved locally, slash commands
- Who's online sidebar, contacts list
- System notifications for new messages and @mentions
- Relay server built with FastAPI — easy to self-host

## Install

```bash
pip install -r requirements.txt
```

## Usage

```bash
# Host a direct connection (E2E encrypted automatically)
python main.py host

# Connect directly to a peer
python main.py connect <ip>

# Connect via relay server
python main.py relay wss://your-relay-server.com

# Connect to a specific room
python main.py relay wss://your-relay-server.com --room friends

# Connect with E2E encryption (both sides must use the same --key)
python main.py relay wss://your-relay-server.com --room friends --key yourpassword
```

First run will ask for a username. Saved to `~/.rootchat/config.json`.  
Chat history is logged to `~/.rootchat/logs/`.

## Encryption

**Direct mode** — encryption is automatic. On first run a persistent X25519 keypair is generated and saved to `~/.rootchat/identity.json`. After connecting, both sides exchange public keys, derive a shared session key, and all messages are encrypted with ChaCha20-Poly1305. A peer fingerprint is shown on connect so you can verify you're talking to the right person.

**Relay mode** — pass `--key <password>` on both sides. The password is never sent over the wire; a symmetric key is derived from it locally (PBKDF2-SHA256) using the room name as a salt, so the same password in different rooms produces different keys. The relay server only sees encrypted blobs.

Both modes show a green `[e2e]` indicator in the status bar when encryption is active.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `ctrl+b` | Toggle sidebar |
| `ctrl+n` | Toggle notifications |
| `ctrl+c` / `escape` | Quit |

## Slash commands

| Command | Description |
|---|---|
| `/room <name>` | Switch relay room |
| `/name <newname>` | Change your username |
| `/add <username>` | Add contact |
| `/remove <username>` | Remove contact |
| `/mute` / `/unmute` | Toggle notifications |
| `/quit` | Exit |

## Relay server

```bash
cd server
pip install -r requirements.txt
python relay.py
```

Or use the setup script on Ubuntu:

```bash
cd server
chmod +x setup.sh
./setup.sh
```

The setup script installs dependencies, creates a venv, and registers a systemd service that auto-starts on boot.

### Caddy reverse proxy

```
your-domain.com {
    reverse_proxy localhost:7332
}
```

## Stack

- [Textual](https://github.com/Textualize/textual) — terminal UI
- [FastAPI](https://fastapi.tiangolo.com/) — relay server
- [websockets](https://websockets.readthedocs.io/) — WebSocket client
- [cryptography](https://cryptography.io/) — X25519, ChaCha20-Poly1305, HKDF, PBKDF2
