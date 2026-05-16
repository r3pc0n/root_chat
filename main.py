from __future__ import annotations

import asyncio
import sys

from config import (
    format_connection,
    load_autostart_initialized,
    load_connections,
    load_last_connection,
    load_username,
    save_autostart_initialized,
    save_connections,
    save_last_connection,
    save_username,
)
from crypto import fingerprint as key_fingerprint, get_or_create_keypair
from network import DEFAULT_PORT, BaseConnection, connect, host, relay_connect
from ui import ChatApp


def _prompt_username() -> str:
    print("\n  root_chat  —  first run\n")
    while True:
        name = input("  choose a username: ").strip()
        if name:
            save_username(name)
            print(f"  saved. welcome, {name}.\n")
            return name
        print("  username cannot be empty.")


def _get_username() -> str:
    return load_username() or _prompt_username()


def _normalize_url(url: str) -> str:
    if url.startswith("http://"):
        return url.replace("http://", "ws://", 1)
    if url.startswith("https://"):
        return url.replace("https://", "wss://", 1)
    if not url.startswith(("ws://", "wss://")):
        return f"wss://{url}"
    return url


def _parse_port(args: list[str]) -> int:
    if "--port" in args:
        return int(args[args.index("--port") + 1])
    return DEFAULT_PORT


def _parse_room(args: list[str]) -> str:
    if "--room" in args:
        return args[args.index("--room") + 1]
    return "default"


def _parse_key(args: list[str]) -> str | None:
    if "--key" in args:
        return args[args.index("--key") + 1]
    return None


def _parse_relay_key(args: list[str]) -> str | None:
    if "--relay-key" in args:
        return args[args.index("--relay-key") + 1]
    return None


def _usage() -> None:
    print("usage:")
    print("  rootchat                         — interactive connection picker")
    print("  rootchat host [--port PORT]")
    print("  rootchat connect <ip> [--port PORT]")
    print("  rootchat relay <url> [--room ROOM] [--relay-key KEY] [--key KEY]")


def _prompt(label: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"  {label}{suffix}: ").strip()
    return value or default


def _setup_connection(existing: dict | None = None) -> dict:
    is_edit = existing is not None
    title = "edit connection" if is_edit else "new connection"
    print(f"\n  root_chat  —  {title}\n")

    name = _prompt("name", existing.get("name", "") if existing else "") or "my connection"

    mode_map = {"relay": "1", "host": "2", "connect": "3"}
    current_mode = mode_map.get(existing.get("mode", ""), "") if existing else ""
    print("\n  mode:")
    print("    [1] relay  (connect via a relay server)")
    print("    [2] host   (wait for a peer to connect)")
    print("    [3] connect (connect directly to a peer)")
    while True:
        suffix = f" [{current_mode}]" if current_mode else ""
        choice = input(f"\n  >{suffix} ").strip() or current_mode
        if choice in ("1", "2", "3"):
            break
        print("  enter 1, 2 or 3")

    if choice == "1":
        default_url = existing.get("server_url", "") if existing else ""
        server_url = _normalize_url(_prompt("server url", default_url).rstrip("/"))
        relay_key = _prompt("relay key       (blank = no auth)", existing.get("relay_key", "") if existing else "")
        room = _prompt("room           ", existing.get("room", "default") if existing else "default") or "default"
        message_key = _prompt("message enc key (blank = none) ", existing.get("message_key", "") if existing else "")
        return {
            "name": name, "mode": "relay",
            "server_url": server_url, "relay_key": relay_key,
            "room": room, "message_key": message_key,
        }
    elif choice == "2":
        default_port = str(existing.get("port", DEFAULT_PORT)) if existing else str(DEFAULT_PORT)
        port_str = _prompt(f"port", default_port)
        port = int(port_str) if port_str.isdigit() else DEFAULT_PORT
        return {"name": name, "mode": "host", "port": port}
    else:
        default_ip = existing.get("ip", "") if existing else ""
        default_port = str(existing.get("port", DEFAULT_PORT)) if existing else str(DEFAULT_PORT)
        ip = _prompt("peer ip", default_ip)
        port_str = _prompt("port", default_port)
        port = int(port_str) if port_str.isdigit() else DEFAULT_PORT
        return {"name": name, "mode": "connect", "ip": ip, "port": port}


def _pick_connection(connections: list[dict]) -> int:
    """Show numbered picker. Returns 0-based index or -1 for new connection."""
    print("\n  root_chat\n")
    for i, c in enumerate(connections):
        print(f"  [{i + 1}] {format_connection(c)}")
    print(f"  [n] + new connection\n")
    while True:
        choice = input("  > ").strip().lower()
        if choice == "n":
            return -1
        if choice.isdigit():
            n = int(choice)
            if 1 <= n <= len(connections):
                return n - 1
        print(f"  enter 1–{len(connections)} or n")


async def _connect_to(username: str, c: dict) -> BaseConnection:
    mode = c["mode"]

    if mode == "relay":
        server_url = c["server_url"]
        room = c.get("room", "default")
        relay_key = c.get("relay_key") or None
        message_key = c.get("message_key") or None
        attempt = 0
        while True:
            try:
                suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
                print(f"  connecting to {server_url} [{room}] ...{suffix}")
                return await relay_connect(server_url, username, room, room_password=message_key, relay_key=relay_key)
            except Exception:
                attempt += 1
                print("  relay not available, retrying in 2s...")
                await asyncio.sleep(2)

    elif mode == "host":
        keypair = get_or_create_keypair()
        port = c.get("port", DEFAULT_PORT)
        print(f"  your key:  {key_fingerprint(keypair.public_bytes)}")
        print(f"  waiting for connection on port {port} ...")
        conn = await host(port, keypair=keypair)
        print(f"  peer key:  {conn.peer_fingerprint}  [verify with your peer]")
        return conn

    elif mode == "connect":
        keypair = get_or_create_keypair()
        ip = c["ip"]
        port = c.get("port", DEFAULT_PORT)
        print(f"  your key:  {key_fingerprint(keypair.public_bytes)}")
        conn = None
        attempt = 0
        while conn is None:
            try:
                suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
                print(f"  connecting to {ip}:{port} ...{suffix}")
                conn = await connect(ip, port, keypair=keypair)
            except (ConnectionRefusedError, OSError):
                attempt += 1
                print("  host not available, retrying in 2s...")
                await asyncio.sleep(2)
        print(f"  peer key:  {conn.peer_fingerprint}  [verify with your peer]")
        return conn

    raise ValueError(f"unknown mode: {mode}")


async def _run_from(username: str, connections: list[dict], idx: int) -> None:
    while True:
        save_last_connection(idx)
        try:
            network_conn = await _connect_to(username, connections[idx])
        except (KeyboardInterrupt, EOFError):
            break

        result = await ChatApp(
            username=username,
            conn=network_conn,
            mode=connections[idx]["mode"],
            connections=connections,
        ).run_async()

        if result == -1:
            conn_dict = _setup_connection()
            connections.append(conn_dict)
            save_connections(connections)
            idx = len(connections) - 1
            print("\n  saved. connecting...\n")
        elif isinstance(result, tuple) and result[0] == "edit":
            n = result[1]
            connections[n] = _setup_connection(existing=connections[n])
            save_connections(connections)
            idx = n
            print("\n  saved. connecting...\n")
        elif isinstance(result, int) and 0 <= result < len(connections):
            connections = load_connections()
            idx = result
        else:
            break


async def _run_interactive(username: str) -> None:
    connections = load_connections()

    if not connections:
        conn_dict = _setup_connection()
        connections = [conn_dict]
        save_connections(connections)
        print("\n  saved. connecting...\n")
        idx = 0
    elif len(connections) == 1:
        print(f"\n  connecting to {connections[0]['name']}...\n")
        idx = 0
    else:
        idx = _pick_connection(connections)
        if idx == -1:
            conn_dict = _setup_connection()
            connections.append(conn_dict)
            save_connections(connections)
            idx = len(connections) - 1
            print("\n  saved. connecting...\n")

    await _run_from(username, connections, idx)


async def _run_autoconnect(username: str) -> None:
    connections = load_connections()
    if not connections:
        await _run_interactive(username)
        return
    idx = load_last_connection()
    if idx < 0 or idx >= len(connections):
        idx = 0
    print(f"\n  auto-connecting to {connections[idx]['name']}...\n")
    await _run_from(username, connections, idx)


async def _run_cli(username: str, args: list[str]) -> None:
    """Original CLI mode — bypasses picker for scripts / power users."""
    mode = args[0]

    if mode == "host":
        keypair = get_or_create_keypair()
        port = _parse_port(args)
        print(f"  your key:  {key_fingerprint(keypair.public_bytes)}")
        print(f"  waiting for connection on port {port} ...")
        conn = await host(port, keypair=keypair)
        print(f"  peer key:  {conn.peer_fingerprint}  [verify with your peer]")
        await ChatApp(username=username, conn=conn, mode="host").run_async()

    elif mode == "connect":
        if len(args) < 2 or args[1].startswith("--"):
            print("  error: connect requires an IP address")
            _usage()
            return
        keypair = get_or_create_keypair()
        ip = args[1]
        port = _parse_port(args)
        print(f"  your key:  {key_fingerprint(keypair.public_bytes)}")
        conn = None
        attempt = 0
        while conn is None:
            try:
                suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
                print(f"  connecting to {ip}:{port} ...{suffix}")
                conn = await connect(ip, port, keypair=keypair)
            except (ConnectionRefusedError, OSError):
                attempt += 1
                print("  host not available, retrying in 2s...")
                await asyncio.sleep(2)
        print(f"  peer key:  {conn.peer_fingerprint}  [verify with your peer]")
        await ChatApp(username=username, conn=conn, mode="client").run_async()

    elif mode == "relay":
        if len(args) < 2 or args[1].startswith("--"):
            print("  error: relay requires a server URL")
            _usage()
            return
        server_url = _normalize_url(args[1].rstrip("/"))
        room = _parse_room(args)
        room_password = _parse_key(args)
        relay_key = _parse_relay_key(args)
        attempt = 0
        conn = None
        while conn is None:
            try:
                suffix = f" (attempt {attempt + 1})" if attempt > 0 else ""
                print(f"  connecting to relay {server_url} [{room}] ...{suffix}")
                conn = await relay_connect(server_url, username, room, room_password=room_password, relay_key=relay_key)
            except Exception:
                attempt += 1
                print("  relay not available, retrying in 2s...")
                await asyncio.sleep(2)
        await ChatApp(username=username, conn=conn, mode="relay").run_async()

    else:
        print(f"  unknown mode: {mode}")
        _usage()


def _maybe_enable_autostart() -> None:
    if load_autostart_initialized():
        return
    try:
        from autostart import enable
        enable()
    except Exception:
        pass
    save_autostart_initialized()


def main() -> None:
    args = sys.argv[1:]
    username = _get_username()
    _maybe_enable_autostart()

    if "--autoconnect" in args:
        asyncio.run(_run_autoconnect(username))
    elif args and args[0] in ("host", "connect", "relay"):
        asyncio.run(_run_cli(username, args))
    elif args:
        _usage()
    else:
        asyncio.run(_run_interactive(username))


if __name__ == "__main__":
    main()
