# root_chat

A minimal terminal P2P chat app for direct or relay-based messaging between people.

## What it does
- Connect directly peer-to-peer over LAN or Tailscale (host/client mode)
- Connect through a self-hosted WebSocket relay server (relay mode)
- Raw, minimal, futuristic terminal UI
- Who's online sidebar with contacts list
- Chat history saved locally per session
- System notifications for new messages and @mentions
- Private messaging — `/dm <user>` opens a dedicated DM room; `/msg <user> <text>` sends a one-off private message
- URL highlighting in messages (green underline)
- @mention autocomplete with Tab
- Auto-reconnect on relay disconnect
- Autostart on login — enabled by default on first run; toggle with `/autostart` (Windows: registry; Linux: XDG .desktop)
- Slash commands: /room, /name, /add, /remove, /mute, /unmute, /dm, /msg, /clear, /autostart, /help, /quit
- **E2E encryption** — direct mode: automatic X25519 handshake + ChaCha20-Poly1305; relay mode: `--key <password>` pre-shared key
- **Connection manager** — saved connections with interactive picker; `/connect edit <n>` to edit; new connection wizard on first run

## Stack
- **Textual** — terminal UI framework (asyncio-based)
- **FastAPI + uvicorn** — relay server with WebSocket support
- **websockets** — WebSocket client for relay mode
- **asyncio** — networking throughout (TCP for direct, WebSocket for relay)
- **cryptography** — X25519 key exchange, ChaCha20-Poly1305 AEAD, HKDF, PBKDF2

## File overview
| File | Purpose |
|---|---|
| `main.py` | Entry point, connection picker, CLI args, connection wizard, autoconnect, retry logic |
| `network.py` | `BaseConnection`, `Connection` (TCP), `RelayConnection` (WebSocket), connect/host/relay_connect; `ChatMessage` with optional `to` field for DMs |
| `ui.py` | Textual `ChatApp` — message display, input, slash commands, status bar, sidebar, @mention autocomplete, auto-reconnect |
| `config.py` | Load/save settings to `~/.rootchat/config.json` — username, connections, last connection, autostart flag, notifications |
| `autostart.py` | Cross-platform autostart: Windows registry / Linux XDG .desktop file (`Terminal=true`) |
| `crypto.py` | E2E encryption — X25519 keypair persistence, DH handshake, ChaCha20-Poly1305 encrypt/decrypt, PBKDF2 room key derivation |
| `history.py` | Per-session log files in `~/.rootchat/logs/` |
| `contacts.py` | Load/save/add/remove contacts in `~/.rootchat/contacts.json` |
| `notifications.py` | OS notifications — Windows (WinRT toast) and Linux (notify-send) |
| `server/relay.py` | FastAPI WebSocket relay — rooms in memory, broadcasts to room members, DM routing via `to` field |
| `server/requirements.txt` | Server deps: fastapi[standard] |
| `server/setup.sh` | Ubuntu setup: venv, deps, systemd service install |
| `server/start.bat` | Start relay server (Windows) |
| `server/start.sh` | Start relay server (Linux) |
| `server/Caddyfile.example` | Caddy reverse proxy snippet |
| `rootchat.iss` | Inno Setup 6 installer script |
| `site/index.html` | Landing page for root-chat.com |

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
| `tab` | Complete @mention |
| `ctrl+c` / `escape` | Quit |

## Slash commands
| Command | Description |
|---|---|
| `/room <name>` | Switch relay room |
| `/name <newname>` | Change username (saved to config) |
| `/dm <user>` | Open a private chat room with a user |
| `/msg <user> <text>` | Send a one-off private message |
| `/add <username>` | Add contact |
| `/remove <username>` | Remove contact |
| `/mute` | Mute notifications for this session |
| `/unmute` | Re-enable notifications |
| `/clear` | Clear the message display |
| `/autostart` | Toggle launch on system login |
| `/connect edit <n>` | Edit saved connection n |
| `/help` | Show all commands |
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
{"user": "alice", "text": "hello", "ts": "14:32", "to": null}
```
The optional `to` field routes DMs — relay delivers only to the named recipient.

### Private messaging (DMs)
- `/dm <user>` — switches to a deterministic room name `dm_<user1>_<user2>` (sorted alphabetically); sends an invite message to the target if they're online
- `/msg <user> <text>` — sends a single message with `to` field set; relay delivers only to that user in the current room
- DM room names are deterministic so both sides land in the same room without coordination

### Relay server
- FastAPI app, port 7332
- Rooms stored in memory as `dict[str, list[tuple[str, WebSocket]]]`
- `/health` endpoint returns active rooms and connected users
- `/ws?username=alice&room=default` — WebSocket endpoint
- Server broadcasts join/leave events as system messages (`"user": "·"`)
- Sidebar polls `/health` every 5 seconds to update online users
- Messages with `to` field are delivered only to the named recipient

### Autostart
- **Windows**: writes `"C:\Program Files\rootchat\rootchat.exe" --autoconnect` to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- **Linux**: writes `~/.config/autostart/rootchat.desktop` with `Terminal=true` so a terminal window opens on login
- Enabled by default on first run (`autostart_initialized` flag in config prevents re-enabling after user disables)
- `--autoconnect` flag skips the picker and connects to the last used connection

### Notifications
- `notifications.py` dispatches to platform-appropriate backend
- Windows: WinRT toast via PowerShell `-EncodedCommand` (no extra deps)
- Linux: `notify-send` subprocess
- Regular message: title `· username`; mention (username in text): title `@ username`
- Mute state is session-only (not persisted)

### E2E encryption

**Direct mode** — automatic, no config needed:
- Persistent X25519 keypair generated on first run, saved to `~/.rootchat/identity.json`
- After TCP connect, host sends its public key (32 bytes), client reads then sends its own; both derive the same session key via `HKDF(SHA-256)` over the raw DH output
- Messages encrypted with ChaCha20-Poly1305 (random 12-byte nonce per message), base64-encoded on the wire
- Peer fingerprint (SHA-256 of public key, first 16 hex chars) printed on connect and shown in the UI

**Relay mode** — opt-in with `--key <password>`:
- PBKDF2-HMAC-SHA256 (100k iterations) derives a 32-byte symmetric key from password + room name
- Same password in different rooms produces different keys
- Only the `text` field of each message is encrypted; `user` and `ts` are still visible to the relay server
- Relay server sees base64 blobs instead of plaintext; system messages (`user == "·"`) are not encrypted

### Network separation
Network code (`network.py`) is intentionally kept separate from UI (`ui.py`) to make a future Go rewrite straightforward.

## Current state
- **Repo**: https://github.com/r3pc0n/root_chat (private)
- **Relay server**: running on homelab VM at `wss://rootchat-server.ddns.net`
- **Relay server host**: Ubuntu 24.04, systemd service `rootchat-relay`, behind Caddy reverse proxy (Caddy on separate machine at 192.168.2.12, relay VM at 192.168.2.4)
- **Relay domain migration pending**: move to `relay.root-chat.com` subdomain (DNS + Caddy config only, no code changes)
- **Windows installer**: `dist/rootchat-setup-v*.exe` via Inno Setup 6 (`rootchat.iss`)
- **Landing page**: `site/index.html` for root-chat.com
- **Tested**: direct mode, relay mode (two machines on different networks), E2E encryption, DMs, autostart (Windows + Linux/Zorin OS)
- **Linux**: run from source; no packaged binary yet

## Development workflow
```powershell
# Run locally (Windows)
cd C:\Users\r3pc0n\OneDrive\Documents\Terminal-Project
pip install -r requirements.txt
python main.py

# Build Windows exe
pyinstaller --onefile --console --name rootchat --collect-data textual --collect-data rich main.py
# Then open rootchat.iss in Inno Setup 6 -> F9 to build installer

# Run locally (Linux)
cd ~/root_chat
source venv/bin/activate
python main.py

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
1. **Go rewrite** — potential future rewrite for single-binary distribution
2. **Relay domain migration** — rootchat-server.ddns.net → relay.root-chat.com (subdomain preferred; DNS + Caddy only)
3. **Interactive web chat** — live chat on root-chat.com pointing to a public relay room (deferred)
4. **Android / iOS app** — same relay protocol, same aesthetic
5. **`/rooms` command** — list active rooms on the relay
6. **Relay latency in status bar**
7. **Auto-update check**
8. **Linux packaging** — .deb or curl install script
9. **Relay-inside-website** — relay can be hosted on an existing domain alongside a website using Caddy path routing; no code changes needed:
   ```
   example.com {
       handle /relay* {
           reverse_proxy localhost:7332
       }
       handle {
           root * /var/www/example.com
           file_server
       }
   }
   ```
   Connect with: `python main.py relay wss://example.com/relay --room friends --key yourpassword`
