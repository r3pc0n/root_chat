from __future__ import annotations

import asyncio
import sys

from config import load_username, save_username
from network import DEFAULT_PORT, connect, host, relay_connect
from ui import ChatApp


def _prompt_username() -> str:
    print("\n  ROOT CHAT  —  first run\n")
    while True:
        name = input("  choose a username: ").strip()
        if name:
            save_username(name)
            print(f"  saved. welcome, {name}.\n")
            return name
        print("  username cannot be empty.")


def _get_username() -> str:
    return load_username() or _prompt_username()


def _parse_port(args: list[str]) -> int:
    if "--port" in args:
        return int(args[args.index("--port") + 1])
    return DEFAULT_PORT


def _parse_room(args: list[str]) -> str:
    if "--room" in args:
        return args[args.index("--room") + 1]
    return "default"


def _normalize_url(url: str) -> str:
    if url.startswith("http://"):
        return url.replace("http://", "ws://", 1)
    if url.startswith("https://"):
        return url.replace("https://", "wss://", 1)
    if not url.startswith(("ws://", "wss://")):
        return f"ws://{url}"
    return url


def _usage() -> None:
    print("usage:")
    print("  python main.py host [--port PORT]")
    print("  python main.py connect <ip> [--port PORT]")
    print("  python main.py relay <server-url> [--room ROOM]")
    print()
    print("examples:")
    print("  python main.py relay ws://localhost:7332")
    print("  python main.py relay wss://relay.example.com --room friends")


async def _run_host(username: str, port: int) -> None:
    print(f"  waiting for connection on port {port} ...")
    conn = await host(port)
    await ChatApp(username=username, conn=conn, mode="host").run_async()


async def _run_connect(username: str, ip: str, port: int) -> None:
    attempt = 0
    while True:
        try:
            suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
            print(f"  connecting to {ip}:{port} ...{suffix}")
            conn = await connect(ip, port)
            break
        except (ConnectionRefusedError, OSError):
            attempt += 1
            print(f"  host not available, retrying in 2s...")
            await asyncio.sleep(2)
    await ChatApp(username=username, conn=conn, mode="client").run_async()


async def _run_relay(username: str, server_url: str, room: str) -> None:
    attempt = 0
    while True:
        try:
            suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
            print(f"  connecting to relay {server_url} [{room}] ...{suffix}")
            conn = await relay_connect(server_url, username, room)
            break
        except Exception:
            attempt += 1
            print(f"  relay not available, retrying in 2s...")
            await asyncio.sleep(2)
    await ChatApp(username=username, conn=conn, mode="relay").run_async()


def main() -> None:
    args = sys.argv[1:]
    if not args:
        _usage()
        sys.exit(1)

    username = _get_username()
    mode = args[0]

    if mode == "host":
        port = _parse_port(args)
        asyncio.run(_run_host(username, port))

    elif mode == "connect":
        if len(args) < 2 or args[1].startswith("--"):
            print("  error: connect requires an IP address")
            _usage()
            sys.exit(1)
        ip = args[1]
        port = _parse_port(args)
        asyncio.run(_run_connect(username, ip, port))

    elif mode == "relay":
        if len(args) < 2 or args[1].startswith("--"):
            print("  error: relay requires a server URL")
            _usage()
            sys.exit(1)
        server_url = _normalize_url(args[1].rstrip("/"))
        room = _parse_room(args)
        asyncio.run(_run_relay(username, server_url, room))

    else:
        print(f"  unknown mode: {mode}")
        _usage()
        sys.exit(1)


if __name__ == "__main__":
    main()
