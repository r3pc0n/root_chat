from __future__ import annotations

import asyncio
import json
import re
import time
import urllib.request
from datetime import datetime
from pathlib import Path

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.widgets import Input, RichLog, Static
from textual.worker import Worker

VERSION = "1.0"
_UPDATE_URL = "https://api.github.com/repos/r3pc0n/root_chat/releases/latest"

from config import format_connection, load_notifications_enabled, save_notifications_enabled, save_username
from contacts import add_contact, load_contacts, remove_contact
from history import History
from network import BaseConnection, ChatMessage, RelayConnection, relay_connect
from notifications import notify


class ChatApp(App):
    CSS = """
    Screen {
        background: #0d0d0d;
        layout: vertical;
    }

    #status-bar {
        height: 1;
        background: #141414;
        layout: horizontal;
    }

    #status-left {
        color: #444444;
        content-align: left middle;
        width: auto;
        padding: 0 2;
    }

    #status-right {
        color: #2a2a2a;
        content-align: right middle;
        width: 1fr;
        padding: 0 2;
    }

    #main {
        height: 1fr;
        layout: horizontal;
    }

    #messages {
        width: 1fr;
        background: #0d0d0d;
        border: solid #1e1e1e;
        padding: 0 1;
        scrollbar-color: #2a2a2a;
        scrollbar-background: #0d0d0d;
    }

    #sidebar {
        width: 24;
        height: 100%;
        background: #0d0d0d;
        border: solid #1e1e1e;
        margin-left: 1;
        padding: 0;
    }

    #hint-bar {
        height: 1;
        background: #0d0d0d;
        color: #2a2a2a;
        padding: 0 2;
        content-align: left middle;
    }

    #chat-input {
        height: 3;
        background: #0d0d0d;
        border: solid #1e1e1e;
        color: #aaaaaa;
        padding: 0 1;
    }

    #chat-input:focus {
        border: solid #2e2e2e;
    }
    """

    BINDINGS = [
        Binding("ctrl+c", "quit", "Quit", show=False),
        Binding("escape", "quit", "Quit", show=False),
        Binding("ctrl+b", "toggle_sidebar", "Toggle sidebar", show=False),
        Binding("ctrl+n", "toggle_notifications", "Toggle notifications", show=False),
        Binding("tab", "complete_mention", "Complete mention", show=False, priority=True),
    ]

    def __init__(self, username: str, conn: BaseConnection, mode: str, connections: list[dict] | None = None) -> None:
        super().__init__()
        self.username = username
        self.conn = conn
        self.mode = mode
        self._connections = connections or []
        self._history: History | None = None
        self._recv_worker: Worker | None = None
        self._switching_room = False
        self._online_users: list[str] = []
        self._latency_ms: int | None = None
        self._sidebar_visible = True
        self._notifications_enabled = load_notifications_enabled()

    def _status_left(self) -> str:
        enc = "  ·  [#4a7c59][[e2e]][/]" if self.conn.encrypted else ""
        if isinstance(self.conn, RelayConnection):
            return f"  root_chat  ·  [[{self.mode}]]  ·  you: {self.username}  ·  room: [[{self.conn._room}]]{enc}"
        return f"  root_chat  ·  [[{self.mode}]]  ·  you: {self.username}  ·  peer: {self.conn.peer_addr}{enc}"

    def _status_right(self) -> str:
        if isinstance(self.conn, RelayConnection):
            latency = f"  ·  {self._latency_ms}ms" if self._latency_ms is not None else ""
            return f"{self.conn._server_url.split('://')[-1]}{latency}  "
        return ""

    def _update_status(self) -> None:
        self.query_one("#status-left", Static).update(self._status_left())
        self.query_one("#status-right", Static).update(self._status_right())

    def compose(self) -> ComposeResult:
        with Horizontal(id="status-bar"):
            yield Static(self._status_left(), id="status-left")
            yield Static(self._status_right(), id="status-right")
        with Horizontal(id="main"):
            yield RichLog(id="messages", highlight=False, markup=True, wrap=True)
            yield Static("", id="sidebar", markup=True)
        yield Static("", id="hint-bar", markup=True)
        yield Input(placeholder="› message...", id="chat-input")

    def on_mount(self) -> None:
        self._history = History(self.conn.peer_addr)
        self.query_one("#chat-input", Input).focus()
        self._system(f"connected to {self.conn.peer_addr}")
        peer_fp = getattr(self.conn, "peer_fingerprint", None)
        if peer_fp:
            self._system(f"peer fingerprint: {peer_fp}")
        self._recv_worker = self.run_worker(self._receive_loop(), exclusive=False)
        self._render_sidebar()
        self.set_interval(5.0, self._refresh_online)
        self.run_worker(self._check_update(), exclusive=False)

    async def _check_update(self) -> None:
        loop = asyncio.get_running_loop()
        latest = await loop.run_in_executor(None, self._fetch_latest_version)
        if latest and latest != VERSION:
            self._system(f"update available: v{latest}  —  root-chat.com")

    def _fetch_latest_version(self) -> str | None:
        try:
            req = urllib.request.Request(_UPDATE_URL, headers={"User-Agent": "rootchat"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                tag = data.get("tag_name", "")
                return tag.lstrip("v") if tag else None
        except Exception:
            return None

    def _do_update(self) -> None:
        import subprocess
        import sys
        latest = self._fetch_latest_version()
        if latest is None:
            self.call_from_thread(self._system, "could not reach update server")
            return
        if latest == VERSION:
            self.call_from_thread(self._system, f"already on latest version ({VERSION})")
            return
        self.call_from_thread(self._system, f"update available: v{latest}  —  updating...")
        if sys.platform == "win32":
            import webbrowser
            webbrowser.open("https://github.com/r3pc0n/root_chat/releases/latest")
            self.call_from_thread(self._system, "opened releases page in browser  —  download and run the installer")
        else:
            try:
                root = Path(__file__).resolve().parent
                result = subprocess.run(
                    ["git", "pull"],
                    cwd=root, capture_output=True, text=True, timeout=30,
                )
                if result.returncode == 0:
                    self.call_from_thread(self._system, "git pull done  —  restart rootchat to use the new version")
                else:
                    self.call_from_thread(self._system, f"git pull failed: {result.stderr.strip()}")
            except Exception as e:
                self.call_from_thread(self._system, f"update failed: {e}")

    async def _receive_loop(self) -> None:
        while True:
            msg = await self.conn.receive()
            if msg is None:
                if not self._switching_room:
                    if isinstance(self.conn, RelayConnection):
                        self.run_worker(self._auto_reconnect(), exclusive=False)
                    else:
                        self._system("connection closed")
                        self.query_one("#chat-input", Input).disabled = True
                break
            self._append(msg.user, msg.text, msg.ts, own=False, to=msg.to)

    async def _auto_reconnect(self) -> None:
        self.query_one("#chat-input", Input).disabled = True
        server_url = self.conn._server_url
        room = self.conn._room
        room_password = getattr(self.conn, "_room_password", None)
        relay_key = getattr(self.conn, "_relay_key", None)

        self._system("connection lost")
        attempt = 0
        while True:
            attempt += 1
            suffix = f"  (attempt {attempt})" if attempt > 1 else ""
            self._system(f"reconnecting...{suffix}")
            try:
                self.conn = await relay_connect(server_url, self.username, room, room_password=room_password, relay_key=relay_key)
                self._online_users = []
                self.query_one("#chat-input", Input).disabled = False
                self._update_status()
                self._render_sidebar()
                self._system("reconnected")
                self._recv_worker = self.run_worker(self._receive_loop(), exclusive=False)
                await self._refresh_online()
                return
            except Exception:
                await asyncio.sleep(3)

    async def _refresh_online(self) -> None:
        if not isinstance(self.conn, RelayConnection):
            return
        loop = asyncio.get_running_loop()
        users, latency = await loop.run_in_executor(None, self._fetch_online_sync)
        self._online_users = users
        self._latency_ms = latency
        self._update_status()
        self._render_sidebar()

    def _fetch_online_sync(self) -> tuple[list[str], int | None]:
        if not isinstance(self.conn, RelayConnection):
            return [], None
        server_url = self.conn._server_url
        room = self.conn._room
        http_url = server_url.replace("wss://", "https://").replace("ws://", "http://")
        try:
            t0 = time.perf_counter()
            with urllib.request.urlopen(f"{http_url}/health", timeout=3) as resp:
                data = json.loads(resp.read())
            latency = round((time.perf_counter() - t0) * 1000)
            return data.get("rooms", {}).get(room, []), latency
        except Exception:
            return self._online_users, self._latency_ms

    def _fetch_all_rooms(self) -> dict[str, list[str]] | None:
        if not isinstance(self.conn, RelayConnection):
            return {}
        http_url = self.conn._server_url.replace("wss://", "https://").replace("ws://", "http://")
        try:
            with urllib.request.urlopen(f"{http_url}/health", timeout=3) as resp:
                data = json.loads(resp.read())
                return data.get("rooms", {})
        except Exception:
            return None

    def _render_sidebar(self) -> None:
        contacts = load_contacts()
        lines: list[str] = [""]  # top padding

        if isinstance(self.conn, RelayConnection):
            lines.append("  [dim]in room[/dim]")
            lines.append("  [dim]───────[/dim]")
            if self._online_users:
                for user in self._online_users:
                    dot = "[#555555]●[/]" if user == self.username else "[#ffaa00]●[/]"
                    label = f"[dim]{user}[/dim]"
                    lines.append(f"  {dot} {label}")
            else:
                lines.append("  [dim]—[/dim]")
            lines.append("")

        lines.append("  [dim]contacts[/dim]")
        lines.append("  [dim]────────[/dim]")
        if contacts:
            for contact in contacts:
                if contact in self._online_users:
                    lines.append(f"  [#ffaa00]●[/] [dim]{contact}[/dim]")
                else:
                    lines.append(f"  [#333333]○[/] [#2a2a2a]{contact}[/]")
        else:
            lines.append("  [dim]none[/dim]")
            lines.append("  [dim]/add <name>[/dim]")

        self.query_one("#sidebar", Static).update("\n".join(lines))

    def action_toggle_sidebar(self) -> None:
        self._sidebar_visible = not self._sidebar_visible
        self.query_one("#sidebar", Static).display = self._sidebar_visible

    # add new commands here — hint bar picks them up automatically
    _COMMANDS = [
        "/update",
        "/rooms",
        "/room <name>",
        "/name <newname>",
        "/dm <user>",
        "/msg <user> <text>",
        "/connect [n|new|edit n|delete n]",
        "/add <username>",
        "/remove <username>",
        "/autostart",
        "/mute",
        "/unmute",
        "/clear",
        "/help",
        "/quit",
    ]

    def _mention_candidates(self) -> list[str]:
        seen = set()
        result = []
        for u in self._online_users + load_contacts():
            if u != self.username and u not in seen:
                seen.add(u)
                result.append(u)
        return result

    def on_input_changed(self, event: Input.Changed) -> None:
        hint_bar = self.query_one("#hint-bar", Static)
        value = event.value

        if value.startswith("/"):
            matches = [c for c in self._COMMANDS if c.startswith(value)] if value != "/" else self._COMMANDS
            hint = "  [dim]·[/dim]  ".join(f"[dim]{m}[/dim]" for m in matches) if matches else "[dim]  no matching command[/dim]"
            hint_bar.update(f"  {hint}")
            hint_bar.display = True
            return

        at_pos = value.rfind("@")
        if at_pos != -1:
            partial = value[at_pos + 1:]
            if " " not in partial:
                candidates = self._mention_candidates()
                matches = [u for u in candidates if u.lower().startswith(partial.lower())] if partial else candidates
                if matches:
                    hint = "  [dim]·[/dim]  ".join(f"[dim]@{m}[/dim]" for m in matches)
                    hint_bar.update(f"  {hint}  [dim](tab)[/dim]")
                    hint_bar.display = True
                    return

        hint_bar.display = False

    def action_complete_mention(self) -> None:
        input_widget = self.query_one("#chat-input", Input)
        if not input_widget.has_focus:
            self.action_focus_next()
            return
        value = input_widget.value
        at_pos = value.rfind("@")
        if at_pos == -1:
            self.action_focus_next()
            return
        partial = value[at_pos + 1:]
        if " " in partial:
            self.action_focus_next()
            return
        candidates = self._mention_candidates()
        matches = [u for u in candidates if u.lower().startswith(partial.lower())] if partial else candidates
        if not matches:
            self.action_focus_next()
            return
        input_widget.value = value[:at_pos + 1] + matches[0] + " "

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        text = event.value.strip()
        if not text:
            return
        event.input.value = ""
        self.query_one("#hint-bar", Static).display = False

        if text.startswith("/"):
            await self._handle_command(text)
            return

        ts = datetime.now().strftime("%H:%M")
        await self.conn.send(ChatMessage(user=self.username, text=text, ts=ts))
        self._append(self.username, text, ts, own=True)

    async def _handle_command(self, text: str) -> None:
        parts = text.split(maxsplit=1)
        cmd = parts[0].lower()
        arg = parts[1].strip() if len(parts) > 1 else ""

        if cmd == "/dm":
            if not isinstance(self.conn, RelayConnection):
                self._system("private chats only available in relay mode")
                return
            if not arg:
                self._system("usage: /dm <username>")
                return
            dm_to = arg.strip()
            if dm_to == self.username:
                self._system("you cannot DM yourself")
                return
            dm_room = "dm_" + "_".join(sorted([self.username, dm_to]))
            ts = datetime.now().strftime("%H:%M")
            if dm_to in self._online_users:
                await self.conn.send(ChatMessage(
                    user=self.username,
                    text=f"wants to start a private chat  ·  /dm {self.username} to join",
                    ts=ts,
                    to=dm_to,
                ))
            await self._reconnect_relay(dm_room, f"private chat with {dm_to}")
        elif cmd == "/msg":
            if not isinstance(self.conn, RelayConnection):
                self._system("private messages only available in relay mode")
                return
            parts_inner = arg.split(maxsplit=1)
            if len(parts_inner) < 2:
                self._system("usage: /msg <username> <message>")
                return
            dm_to, dm_text = parts_inner[0], parts_inner[1].strip()
            if not dm_text:
                self._system("usage: /msg <username> <message>")
                return
            if dm_to not in self._online_users:
                self._system(f"{dm_to} is not in this room")
                return
            ts = datetime.now().strftime("%H:%M")
            await self.conn.send(ChatMessage(user=self.username, text=dm_text, ts=ts, to=dm_to))
            self._append(self.username, dm_text, ts, own=True, to=dm_to)
        elif cmd == "/quit":
            self._exit_with(None)
        elif cmd == "/connect":
            if not self._connections:
                self._system("no saved connections  (use CLI args to connect)")
                return
            if not arg:
                for i, c in enumerate(self._connections):
                    self._system(f"  [{i + 1}] {format_connection(c)}")
                self._system("  [n] + new connection")
                self._system("  /connect <n>  ·  /connect new  ·  /connect edit <n>  ·  /connect delete <n>")
            elif arg == "new":
                self._exit_with(-1)
            elif arg.startswith("edit "):
                try:
                    n = int(arg.split()[1]) - 1
                    if n < 0 or n >= len(self._connections):
                        self._system(f"  enter 1–{len(self._connections)}")
                        return
                    self._exit_with(("edit", n))
                except (ValueError, IndexError):
                    self._system("usage: /connect edit <number>")
            elif arg.startswith("delete "):
                try:
                    n = int(arg.split()[1]) - 1
                    if n < 0 or n >= len(self._connections):
                        self._system(f"  enter 1–{len(self._connections)}")
                        return
                    from config import save_connections
                    name = self._connections[n]["name"]
                    self._connections.pop(n)
                    save_connections(self._connections)
                    self._system(f"  deleted [{name}]")
                except (ValueError, IndexError):
                    self._system("usage: /connect delete <number>")
            else:
                try:
                    n = int(arg) - 1
                    if n < 0 or n >= len(self._connections):
                        self._system(f"  enter 1–{len(self._connections)}")
                        return
                    self._exit_with(n)
                except ValueError:
                    self._system("usage: /connect <number>  ·  /connect new  ·  /connect edit <n>  ·  /connect delete <n>")
        elif cmd == "/name":
            if not arg:
                self._system("usage: /name <newname>")
                return
            self.username = arg
            save_username(self.username)
            if isinstance(self.conn, RelayConnection):
                await self._reconnect_relay(self.conn._room, f"you are now known as {self.username}")
            else:
                self._update_status()
                self._system(f"you are now known as {self.username}")
        elif cmd == "/room":
            if not arg:
                self._system("usage: /room <name>")
                return
            if not isinstance(self.conn, RelayConnection):
                self._system("room switching only available in relay mode")
                return
            if arg == self.conn._room:
                self._system(f"already in [{arg}]")
                return
            await self._reconnect_relay(arg, f"joined [{arg}]")
        elif cmd == "/rooms":
            if not isinstance(self.conn, RelayConnection):
                self._system("rooms only available in relay mode")
                return
            loop = asyncio.get_event_loop()
            rooms = await loop.run_in_executor(None, self._fetch_all_rooms)
            if rooms is None:
                self._system("could not reach relay server")
                return
            if not rooms:
                self._system("no active rooms")
                return
            current = self.conn._room
            for name, users in sorted(rooms.items()):
                marker = "▶" if name == current else " "
                self._system(f"{marker} \[{name}]  —  {len(users)} online: {', '.join(users)}")
        elif cmd == "/add":
            if not arg:
                self._system("usage: /add <username>")
                return
            if add_contact(arg):
                self._system(f"added {arg} to contacts")
                self._render_sidebar()
            else:
                self._system(f"{arg} is already in your contacts")
        elif cmd == "/autostart":
            try:
                from autostart import disable, enable, is_enabled
                if is_enabled():
                    disable()
                    self._system("autostart disabled")
                else:
                    enable()
                    self._system("autostart enabled  —  rootchat will launch on login")
            except Exception as e:
                self._system(f"autostart not available: {e}")
        elif cmd == "/mute":
            self._notifications_enabled = False
            save_notifications_enabled(False)
            self._system("notifications muted  (ctrl+n or /unmute to re-enable)")
        elif cmd == "/unmute":
            self._notifications_enabled = True
            save_notifications_enabled(True)
            self._system("notifications on")
        elif cmd == "/remove":
            if not arg:
                self._system("usage: /remove <username>")
                return
            if remove_contact(arg):
                self._system(f"removed {arg} from contacts")
                self._render_sidebar()
            else:
                self._system(f"{arg} is not in your contacts")
        elif cmd == "/clear":
            self.query_one("#messages", RichLog).clear()
        elif cmd == "/update":
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, self._do_update)
        elif cmd == "/help":
            self._system("/update                check for and apply updates")
            self._system("/rooms                 list active rooms on the relay")
            self._system("/room <name>          switch relay room")
            self._system("/name <newname>        change your username")
            self._system("/dm <user>             open a private chat")
            self._system("/autostart             toggle launch on system login")
            self._system("/msg <user> <text>     send a one-off private message")
            self._system("/connect               list saved connections")
            self._system("/connect <n>           switch to connection n")
            self._system("/connect new           add a new connection")
            self._system("/connect edit <n>      edit connection n")
            self._system("/connect delete <n>    delete connection n")
            self._system("/add <username>         add to contacts")
            self._system("/remove <username>      remove from contacts")
            self._system("/mute                  mute notifications")
            self._system("/unmute                re-enable notifications")
            self._system("/quit                  exit")
        else:
            self._system(f"unknown command: {cmd}  (try /help)")

    async def _reconnect_relay(self, room: str, success_msg: str) -> None:
        server_url = self.conn._server_url
        room_password = getattr(self.conn, "_room_password", None)
        relay_key = getattr(self.conn, "_relay_key", None)

        self._switching_room = True
        if self._recv_worker:
            self._recv_worker.cancel()
        self.conn.close()

        try:
            self.conn = await relay_connect(server_url, self.username, room, room_password=room_password, relay_key=relay_key)
        except Exception:
            self._switching_room = False
            self._system("failed to reconnect")
            return

        self._switching_room = False
        self._online_users = []
        self.query_one("#chat-input", Input).disabled = False
        self._update_status()
        self._render_sidebar()
        self._system(success_msg)
        self._recv_worker = self.run_worker(self._receive_loop(), exclusive=False)
        await self._refresh_online()

    _URL_RE = re.compile(r'https?://\S+')

    def _append(self, user: str, text: str, ts: str, own: bool, to: str | None = None) -> None:
        log = self.query_one("#messages", RichLog)
        name_color = "#888888" if own else "#ffaa00"

        line = Text(no_wrap=False)
        line.append(ts, style="dim")
        line.append("  ")
        line.append(user, style=name_color)
        if to:
            dm_label = f" → {to}" if own else " → you"
            line.append(dm_label, style="#555555")
        line.append("  ")

        last = 0
        for m in self._URL_RE.finditer(text):
            if m.start() > last:
                line.append(text[last:m.start()])
            line.append(m.group(), style="#4a7c59 underline")
            last = m.end()
        line.append(text[last:])

        log.write(line)
        if self._history:
            self._history.log(ts, user, text)
        if not own:
            self._notify(user, text)

    def _notify(self, user: str, text: str) -> None:
        if not self._notifications_enabled:
            return
        mentioned = self.username.lower() in text.lower()
        title = f"· {user}" if not mentioned else f"@ {user}"
        notify(title, text)

    def action_toggle_notifications(self) -> None:
        self._notifications_enabled = not self._notifications_enabled
        save_notifications_enabled(self._notifications_enabled)
        state = "on" if self._notifications_enabled else "muted"
        self._system(f"notifications {state}")

    def _system(self, msg: str) -> None:
        log = self.query_one("#messages", RichLog)
        log.write(Text.from_markup(f"[dim]  ·  {msg}[/dim]"))
        if self._history:
            self._history.log_system(msg)

    def _exit_with(self, result) -> None:
        self.conn.close()
        if self._history:
            self._history.close()
        self.exit(result=result)

    def action_quit(self) -> None:
        self._exit_with(None)
