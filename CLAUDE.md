# root_chat

A minimal terminal P2P chat app for direct or relay-based messaging between people.

## What it does
- Connect directly peer-to-peer over LAN or Tailscale (host/client mode)
- Connect through a self-hosted WebSocket relay server (relay mode)
- Raw, minimal, futuristic terminal UI
- Chat history saved locally per session
- Slash commands: /name, /room, /quit

## Stack
- **Textual** — terminal UI framework (asyncio-based)
- **FastAPI + uvicorn** — relay server with WebSocket support
- **websockets** — WebSocket client for relay mode
- **asyncio** — networking throughout (TCP for direct, WebSocket for relay)

## File overview
| File | Purpose |
|---|---|
| `main.py` | Entry point, CLI args (host / connect / relay), connection retry logic |
| `network.py` | `BaseConnection`, `Connection` (TCP), `RelayConnection` (WebSocket), connect/host/relay_connect |
| `ui.py` | Textual `ChatApp` — message display, input, slash commands, status bar |
| `config.py` | Load/save username to `~/.rootchat/config.json` |
| `history.py` | Per-session log files in `~/.rootchat/logs/` |
| `server/relay.py` | FastAPI WebSocket relay — rooms in memory, broadcasts to room members |
| `server/requirements.txt` | Server deps: fastapi[standard] |
| `server/setup.sh` | Ubuntu setup: venv, deps, systemd service install |
| `server/start.bat` | Start relay server (Windows) |
| `server/start.sh` | Start relay server (Linux) |
| `server/Caddyfile.example` | Caddy reverse proxy snippet |

## Architecture

### Connection types
- `BaseConnection` — shared interface (send, receive, peer_addr, close)
- `Connection` — wraps asyncio TCP streams (direct mode)
- `RelayConnection` — wraps a websocket (relay mode)
- `ChatApp` accepts any `BaseConnection` — UI is identical for all modes

### Message format
Newline-delimited JSON over TCP, plain JSON strings over WebSocket:
```json
{"user": "alice", "text": "hello", "ts": "14:32"}
```

### Relay server
- FastAPI app, port 7332
- Rooms stored in memory as `dict[str, list[tuple[str, WebSocket]]]`
- `/health` endpoint returns active rooms and connected users
- `/ws?username=alice&room=default` — WebSocket endpoint
- Server broadcasts join/leave events as system messages (`"user": "·"`)

### Network separation
Network code (`network.py`) is intentionally kept separate from UI (`ui.py`) to make a future Go rewrite straightforward.

## Current state
- **Repo**: https://github.com/r3pc0n/root_chat (private)
- **Relay server**: running on homelab VM, accessible at `wss://rootchat-server.ddns.net`
- **Relay server host**: Ubuntu 24.04, systemd service `rootchat-relay`, behind Caddy reverse proxy
- **Tested**: direct mode (same machine), relay mode (two machines on different networks)

## Development workflow
```powershell
# Run locally (Windows)
cd C:\Users\r3pc0n\OneDrive\Documents\Terminal-Project
pip install -r requirements.txt
python main.py host
python main.py connect 127.0.0.1
python main.py relay wss://rootchat-server.ddns.net --room test

# Start relay server locally for testing
cd server
pip install -r requirements.txt
python relay.py

# Commit and push
git add .
git commit -m "description"
git push
```

## Relay server management
```bash
# On the relay server VM
sudo systemctl status rootchat-relay
sudo systemctl restart rootchat-relay
sudo journalctl -u rootchat-relay -f
```

## Known issues / next steps
1. ~~**Rooms** — /room command to switch rooms mid-session~~ done
2. **Who's online** — sidebar or status showing connected users in the room
3. **End-to-end encryption** — server currently sees plaintext messages (TLS in transit only)
4. **Go rewrite** — potential future rewrite for single-binary distribution
