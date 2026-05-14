from __future__ import annotations

from datetime import datetime

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Input, RichLog, Static

from config import save_username
from history import History
from network import BaseConnection, ChatMessage


class ChatApp(App):
    CSS = """
    Screen {
        background: #0d0d0d;
        layout: vertical;
    }

    #status {
        height: 1;
        background: #141414;
        color: #444444;
        padding: 0 2;
        content-align: left middle;
    }

    #messages {
        height: 1fr;
        background: #0d0d0d;
        border: solid #1e1e1e;
        padding: 0 1;
        scrollbar-color: #2a2a2a;
        scrollbar-background: #0d0d0d;
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
    ]

    def __init__(self, username: str, conn: BaseConnection, mode: str) -> None:
        super().__init__()
        self.username = username
        self.conn = conn
        self.mode = mode
        self._history: History | None = None

    def _status_text(self) -> str:
        return f"  ROOT CHAT  ·  [{self.mode}]  ·  you: {self.username}  ·  peer: {self.conn.peer_addr}"

    def compose(self) -> ComposeResult:
        yield Static(self._status_text(), id="status")
        yield RichLog(id="messages", highlight=False, markup=True, wrap=True)
        yield Input(placeholder="› message...", id="chat-input")

    def on_mount(self) -> None:
        self._history = History(self.conn.peer_addr)
        self.query_one("#chat-input", Input).focus()
        self._system(f"connected to {self.conn.peer_addr}")
        self.run_worker(self._receive_loop(), exclusive=False)

    async def _receive_loop(self) -> None:
        while True:
            msg = await self.conn.receive()
            if msg is None:
                self._system("connection closed")
                self.query_one("#chat-input", Input).disabled = True
                break
            self._append(msg.user, msg.text, msg.ts, own=False)

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        text = event.value.strip()
        if not text:
            return
        event.input.value = ""

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
            self.query_one("#status", Static).update(self._status_text())
            self._system(f"you are now known as {self.username}")
        else:
            self._system(f"unknown command: {cmd}  (try /name or /quit)")

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
