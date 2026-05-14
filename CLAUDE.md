# root_chat

A minimal terminal P2P chat app for direct or relay-based messaging between people.

## What it does
- Connect directly peer-to-peer over LAN or Tailscale (host/client mode)
- Connect through a self-hosted WebSocket relay server (relay mode)
- Raw, minimal, futuristic terminal UI
- Who's online sidebar with contacts list
- Chat history saved locally per session
- System notifications for new messages and @mentions
- Slash commands: /room, /name, /add, /remove, /mute, /unmute, /quit

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
| `ui.py` | Textual `ChatApp` — message display, input, slash commands, status bar, sidebar |
| `config.py` | Load/save username to `~/.rootchat/config.json` |
| `history.py` | Per-session log files in `~/.rootchat/logs/` |
| `contacts.py` | Load/save/add/remove contacts in `~/.rootchat/contacts.json` |
| `notifications.py` | OS notifications — Windows (WinRT toast) and Linux (notify-send) |
| `server/relay.py` | FastAPI WebSocket relay — rooms in memory, broadcasts to room members |
| `server/requirements.txt` | Server deps: fastapi[standard] |
| `server/setup.sh` | Ubuntu setup: venv, deps, systemd service install |
| `server/start.bat` | Start relay server (Windows) |
| `server/start.sh` | Start relay server (Linux) |
| `server/Caddyfile.example` | Caddy reverse proxy snippet |

## UI layout
```
┌─ status bar ──────────────────────────────── server url ─┐
├─ messages ──────────────────────────┐ ┌─ sidebar ────────┤
│                                     │ │  in room         │
│                                     │ │  ● alice         │
│                                     │ │  ● r3pc0n        │
│                                     │ │                  │
│                                     │ │  contacts        │
│                                     │ │  ● alice         │
│                                     │ │  ○ bob           │
├─ hint bar (appears when typing /) ──┴─┴──────────────────┤
├─ input ──────────────────────────────────────────────────┤
```

## Keyboard shortcuts
| Key | Action |
|---|---|
| `ctrl+b` | Toggle sidebar |
| `ctrl+n` | Toggle notifications (mute/unmute) |
| `ctrl+c` / `escape` | Quit |

## Slash commands
| Command | Description |
|---|---|
| `/room <name>` | Switch relay room |
| `/name <newname>` | Change username (saved to config) |
| `/add <username>` | Add contact |
| `/remove <username>` | Remove contact |
| `/mute` | Mute notifications for this session |
| `/unmute` | Re-enable notifications |
| `/quit` | Exit |

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
- Sidebar polls `/health` every 5 seconds to update online users

### Notifications
- `notifications.py` dispatches to platform-appropriate backend
- Windows: WinRT toast via PowerShell `-EncodedCommand` (no extra deps)
- Linux: `notify-send` subprocess
- Regular message: title `· username`; mention (username in text): title `@ username`
- Mute state is session-only (not persisted)

### Network separation
Network code (`network.py`) is intentionally kept separate from UI (`ui.py`) to make a future Go rewrite straightforward.

## Current state
- **Repo**: https://github.com/r3pc0n/root_chat (private)
- **Relay server**: running on homelab VM at `wss://rootchat-server.ddns.net`
- **Relay server host**: Ubuntu 24.04, systemd service `rootchat-relay`, behind Caddy reverse proxy (Caddy on separate machine at 192.168.2.12, relay VM at 192.168.2.4)
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

## Parked / future
1. **End-to-end encryption** — server currently sees plaintext (TLS in transit only); E2E for direct mode is feasible, group E2E is complex
2. **Go rewrite** — potential future rewrite for single-binary distribution
3. **Relay server** — currently no authentication; anyone with the URL can connect
4. **Notification mute persistence** — currently session-only
