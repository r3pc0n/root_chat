from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag

from crypto import KeyPair, decrypt, derive_room_key, encrypt, fingerprint, handshake_client, handshake_host

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

    @property
    def encrypted(self) -> bool:
        return False

    async def send(self, msg: ChatMessage) -> None:
        raise NotImplementedError

    async def receive(self) -> ChatMessage | None:
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class Connection(BaseConnection):
    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        encryption_key: bytes | None = None,
        peer_fingerprint: str | None = None,
    ) -> None:
        self._reader = reader
        self._writer = writer
        self._encryption_key = encryption_key
        self.peer_fingerprint = peer_fingerprint

    @property
    def peer_addr(self) -> str:
        peer = self._writer.get_extra_info("peername")
        return f"{peer[0]}:{peer[1]}" if peer else "unknown"

    @property
    def encrypted(self) -> bool:
        return self._encryption_key is not None

    async def send(self, msg: ChatMessage) -> None:
        if self._encryption_key:
            self._writer.write(encrypt(self._encryption_key, _encode(msg).rstrip(b"\n")) + b"\n")
        else:
            self._writer.write(_encode(msg))
        await self._writer.drain()

    async def receive(self) -> ChatMessage | None:
        try:
            line = await self._reader.readline()
            if not line:
                return None
            if self._encryption_key:
                try:
                    return _decode_bytes(decrypt(self._encryption_key, line))
                except (InvalidTag, ValueError, KeyError):
                    return None
            return _decode_bytes(line)
        except (ConnectionResetError, asyncio.IncompleteReadError, OSError):
            return None

    def close(self) -> None:
        self._writer.close()


class RelayConnection(BaseConnection):
    def __init__(
        self,
        ws,
        server_url: str,
        room: str,
        encryption_key: bytes | None = None,
        room_password: str | None = None,
        relay_key: str | None = None,
    ) -> None:
        self._ws = ws
        self._server_url = server_url
        self._room = room
        self._encryption_key = encryption_key
        self._room_password = room_password
        self._relay_key = relay_key

    @property
    def peer_addr(self) -> str:
        return f"{self._server_url} [{self._room}]"

    @property
    def encrypted(self) -> bool:
        return self._encryption_key is not None

    async def send(self, msg: ChatMessage) -> None:
        text = encrypt(self._encryption_key, msg.text.encode()).decode() if self._encryption_key else msg.text
        await self._ws.send(json.dumps({"user": msg.user, "text": text, "ts": msg.ts}))

    async def receive(self) -> ChatMessage | None:
        try:
            data = await self._ws.recv()
            msg = _decode_str(data)
            if self._encryption_key and msg.user != "·":
                try:
                    decrypted = decrypt(self._encryption_key, msg.text.encode()).decode()
                    return ChatMessage(user=msg.user, text=decrypted, ts=msg.ts)
                except (InvalidTag, ValueError, KeyError):
                    return None
            return msg
        except Exception:
            return None

    def close(self) -> None:
        try:
            asyncio.get_running_loop().create_task(self._ws.close())
        except RuntimeError:
            pass


async def host(port: int = DEFAULT_PORT, keypair: KeyPair | None = None) -> Connection:
    loop = asyncio.get_running_loop()
    accepted: asyncio.Future = loop.create_future()

    async def _handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        if not accepted.done():
            accepted.set_result((reader, writer))

    server = await asyncio.start_server(_handle, "0.0.0.0", port)
    reader, writer = await accepted
    server.close()
    await server.wait_closed()
    if keypair:
        key, peer_pub = await handshake_host(reader, writer, keypair)
        return Connection(reader, writer, encryption_key=key, peer_fingerprint=fingerprint(peer_pub))
    return Connection(reader, writer)


async def connect(ip: str, port: int = DEFAULT_PORT, keypair: KeyPair | None = None) -> Connection:
    reader, writer = await asyncio.open_connection(ip, port)
    if keypair:
        key, peer_pub = await handshake_client(reader, writer, keypair)
        return Connection(reader, writer, encryption_key=key, peer_fingerprint=fingerprint(peer_pub))
    return Connection(reader, writer)


async def relay_connect(
    server_url: str,
    username: str,
    room: str = "default",
    room_password: str | None = None,
    relay_key: str | None = None,
) -> RelayConnection:
    import websockets
    url = f"{server_url}/ws?username={username}&room={room}"
    headers = {"Authorization": f"Bearer {relay_key}"} if relay_key else {}
    ws = await websockets.connect(url, extra_headers=headers)
    key = derive_room_key(room_password, room) if room_password else None
    return RelayConnection(ws, server_url, room, encryption_key=key, room_password=room_password, relay_key=relay_key)
