from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass

DEFAULT_PORT = 7331
DEFAULT_RELAY_PORT = 7332


@dataclass
class ChatMessage:
    user: str
    text: str
    ts: str


def _encode(msg: ChatMessage) -> bytes:
    return (json.dumps({"user": msg.user, "text": msg.text, "ts": msg.ts}) + "\n").encode()


def _decode_bytes(line: bytes) -> ChatMessage:
    data = json.loads(line.decode().strip())
    return ChatMessage(**data)


def _decode_str(text: str) -> ChatMessage:
    data = json.loads(text)
    return ChatMessage(**data)


class BaseConnection:
    @property
    def peer_addr(self) -> str:
        raise NotImplementedError

    async def send(self, msg: ChatMessage) -> None:
        raise NotImplementedError

    async def receive(self) -> ChatMessage | None:
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class Connection(BaseConnection):
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._reader = reader
        self._writer = writer

    @property
    def peer_addr(self) -> str:
        peer = self._writer.get_extra_info("peername")
        return f"{peer[0]}:{peer[1]}" if peer else "unknown"

    async def send(self, msg: ChatMessage) -> None:
        self._writer.write(_encode(msg))
        await self._writer.drain()

    async def receive(self) -> ChatMessage | None:
        try:
            line = await self._reader.readline()
            return _decode_bytes(line) if line else None
        except (ConnectionResetError, asyncio.IncompleteReadError, OSError):
            return None

    def close(self) -> None:
        self._writer.close()


class RelayConnection(BaseConnection):
    def __init__(self, ws, server_url: str, room: str) -> None:
        self._ws = ws
        self._server_url = server_url
        self._room = room

    @property
    def peer_addr(self) -> str:
        return f"{self._server_url} [{self._room}]"

    async def send(self, msg: ChatMessage) -> None:
        await self._ws.send(json.dumps({"user": msg.user, "text": msg.text, "ts": msg.ts}))

    async def receive(self) -> ChatMessage | None:
        try:
            data = await self._ws.recv()
            return _decode_str(data)
        except Exception:
            return None

    def close(self) -> None:
        try:
            asyncio.get_running_loop().create_task(self._ws.close())
        except RuntimeError:
            pass


async def host(port: int = DEFAULT_PORT) -> Connection:
    loop = asyncio.get_running_loop()
    accepted: asyncio.Future = loop.create_future()

    async def _handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        if not accepted.done():
            accepted.set_result((reader, writer))

    server = await asyncio.start_server(_handle, "0.0.0.0", port)
    reader, writer = await accepted
    server.close()
    await server.wait_closed()
    return Connection(reader, writer)


async def connect(ip: str, port: int = DEFAULT_PORT) -> Connection:
    reader, writer = await asyncio.open_connection(ip, port)
    return Connection(reader, writer)


async def relay_connect(server_url: str, username: str, room: str = "default") -> RelayConnection:
    import websockets
    url = f"{server_url}/ws?username={username}&room={room}"
    ws = await websockets.connect(url)
    return RelayConnection(ws, server_url, room)
