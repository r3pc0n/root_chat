from __future__ import annotations

import asyncio
import json
import urllib.request
from datetime import datetime

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.widgets import Input, RichLog, Static
from textual.worker import Worker

from config import save_username
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
    ]

    def __init__(self, username: str, conn: BaseConnection, mode: str) -> None:
        super().__init__()
        self.username = username
        self.conn = conn
        self.mode = mode
        self._history: History | None = None
        self._recv_worker: Worker | None = None
        self._switching_room = False
        self._online_users: list[str] = []
        self._sidebar_visible = True
        self._notifications_enabled = True

    def _status_left(self) -> str:
        if isinstance(self.conn, RelayConnection):
            return f"  ROOT CHAT  ·  [{self.mode}]  ·  you: {self.username}  ·  room: {self.conn._room}"
        return f"  ROOT CHAT  ·  [{self.mode}]  ·  you: {self.username}  ·  peer: {self.conn.peer_addr}"

    def _status_right(self) -> str:
        if isinstance(self.conn, RelayConnection):
            return f"{self.conn._server_url.split('://')[-1]}  "
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
        self._recv_worker = self.run_worker(self._receive_loop(), exclusive=False)
        self._render_sidebar()
        self.set_interval(5.0, self._refresh_online)

    async def _receive_loop(self) -> None:
        while True:
            msg = await self.conn.receive()
            if msg is None:
                if not self._switching_room:
                    self._system("connection closed")
                    self.query_one("#chat-input", Input).disabled = True
                break
            self._append(msg.user, msg.text, msg.ts, own=False)

    async def _refresh_online(self) -> None:
        if not isinstance(self.conn, RelayConnection):
            return
        loop = asyncio.get_running_loop()
        users = await loop.run_in_executor(None, self._fetch_online_sync)
        self._online_users = users
        self._render_sidebar()

    def _fetch_online_sync(self) -> list[str]:
        if not isinstance(self.conn, RelayConnection):
            return []
        server_url = self.conn._server_url
        room = self.conn._room
        http_url = server_url.replace("wss://", "https://").replace("ws://", "http://")
        try:
            with urllib.request.urlopen(f"{http_url}/health", timeout=3) as resp:
                data = json.loads(resp.read())
                return data.get("rooms", {}).get(room, [])
        except Exception:
            return self._online_users

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
        "/room <name>",
        "/name <newname>",
        "/add <username>",
        "/remove <username>",
        "/mute",
        "/unmute",
        "/quit",
    ]

    def on_input_changed(self, event: Input.Changed) -> None:
        hint_bar = self.query_one("#hint-bar", Static)
        value = event.value
        if not value.startswith("/"):
            hint_bar.display = False
            return
        matches = [c for c in self._COMMANDS if c.startswith(value)] if value != "/" else self._COMMANDS
        if matches:
            hint = "  [dim]·[/dim]  ".join(f"[dim]{m}[/dim]" for m in matches)
        else:
            hint = "[dim]  no matching command[/dim]"
        hint_bar.update(f"  {hint}")
        hint_bar.display = True

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

        if cmd == "/quit":
            self.action_quit()
        elif cmd == "/name":
            if not arg:
                self._system("usage: /name <newname>")
                return
            self.username = arg
            save_username(self.username)
            self._update_status()
            self._system(f"you are now known as {self.username}")
        elif cmd == "/room":
            if not arg:
                self._system("usage: /room <name>")
                return
            await self._switch_room(arg)
        elif cmd == "/add":
            if not arg:
                self._system("usage: /add <username>")
                return
            if add_contact(arg):
                self._system(f"added {arg} to contacts")
                self._render_sidebar()
            else:
                self._system(f"{arg} is already in your contacts")
        elif cmd == "/mute":
            self._notifications_enabled = False
            self._system("notifications muted  (ctrl+n or /unmute to re-enable)")
        elif cmd == "/unmute":
            self._notifications_enabled = True
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
        else:
            self._system(f"unknown command: {cmd}  (try /name, /room, /add, /remove, /quit)")

    async def _switch_room(self, new_room: str) -> None:
        if not isinstance(self.conn, RelayConnection):
            self._system("room switching only available in relay mode")
            return

        server_url = self.conn._server_url
        old_room = self.conn._room

        if new_room == old_room:
            self._system(f"already in [{old_room}]")
            return

        self._system(f"switching to [{new_room}]...")
        self._switching_room = True

        if self._recv_worker:
            self._recv_worker.cancel()
        self.conn.close()

        try:
            self.conn = await relay_connect(server_url, self.username, new_room)
        except Exception:
            self._switching_room = False
            self._system("failed to connect to new room")
            return

        self._switching_room = False
        self._online_users = []
        self.query_one("#chat-input", Input).disabled = False
        self._update_status()
        self._render_sidebar()
        self._system(f"joined [{new_room}]")
        self._recv_worker = self.run_worker(self._receive_loop(), exclusive=False)
        await self._refresh_online()

    def _append(self, user: str, text: str, ts: str, own: bool) -> None:
        log = self.query_one("#messages", RichLog)
        name_color = "#888888" if own else "#ffaa00"
        log.write(
            Text.from_markup(
                f"[dim]{ts}[/dim]  [{name_color}]{user}[/{name_color}]  {text}"
            )
        )
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
        state = "on" if self._notifications_enabled else "muted"
        self._system(f"notifications {state}")

    def _system(self, msg: str) -> None:
        log = self.query_one("#messages", RichLog)
        log.write(Text.from_markup(f"[dim]  ·  {msg}[/dim]"))
        if self._history:
            self._history.log_system(msg)

    def action_quit(self) -> None:
        self.conn.close()
        if self._history:
            self._history.close()
        self.exit()
