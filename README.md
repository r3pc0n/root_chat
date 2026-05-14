# RootChat

A minimal terminal chat app for direct P2P messaging or relay-based communication. Built with Python and Textual.

## Features

- Push-to-talk style terminal UI — raw, minimal, futuristic
- **Direct mode** — connect peer-to-peer over LAN or Tailscale
- **Relay mode** — connect through a self-hosted relay server (WebSocket)
- Usernames, chat history saved locally, slash commands
- Relay server built with FastAPI — easy to self-host

## Install

```bash
pip install -r requirements.txt
```

## Usage

```bash
# Host a direct connection
python main.py host

# Connect directly to a peer
python main.py connect <ip>

# Connect via relay server
python main.py relay wss://your-relay-server.com

# Connect to a specific room
python main.py relay wss://your-relay-server.com --room friends
```

First run will ask for a username. Saved to `~/.rootchat/config.json`.  
Chat history is logged to `~/.rootchat/logs/`.

## Slash commands

| Command | Description |
|---|---|
| `/name <newname>` | Change your username |
| `/quit` | Exit the chat |

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
