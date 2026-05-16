import json
from pathlib import Path

_CONFIG_FILE = Path.home() / ".rootchat" / "config.json"


def _load() -> dict:
    if _CONFIG_FILE.exists():
        return json.loads(_CONFIG_FILE.read_text())
    return {}


def _save(data: dict) -> None:
    _CONFIG_FILE.parent.mkdir(exist_ok=True)
    _CONFIG_FILE.write_text(json.dumps(data))


def load_username() -> str | None:
    return _load().get("username")


def save_username(username: str) -> None:
    data = _load()
    data["username"] = username
    _save(data)


def load_notifications_enabled() -> bool:
    return _load().get("notifications_enabled", True)


def save_notifications_enabled(enabled: bool) -> None:
    data = _load()
    data["notifications_enabled"] = enabled
    _save(data)


def load_connections() -> list[dict]:
    return _load().get("connections", [])


def save_connections(connections: list[dict]) -> None:
    data = _load()
    data["connections"] = connections
    _save(data)


def load_last_connection() -> int:
    return _load().get("last_connection", 0)


def save_last_connection(index: int) -> None:
    data = _load()
    data["last_connection"] = index
    _save(data)


def load_autostart_initialized() -> bool:
    return _load().get("autostart_initialized", False)


def save_autostart_initialized() -> None:
    data = _load()
    data["autostart_initialized"] = True
    _save(data)


def load_show_welcome() -> bool:
    return _load().get("show_welcome", True)


def save_show_welcome(enabled: bool) -> None:
    data = _load()
    data["show_welcome"] = enabled
    _save(data)


def format_connection(c: dict) -> str:
    name = c.get("name", "unnamed")
    mode = c.get("mode", "?")
    if mode == "relay":
        url = c.get("server_url", "?").split("://")[-1]
        room = c.get("room", "default")
        tags = []
        if c.get("relay_key"):
            tags.append("auth")
        if c.get("message_key"):
            tags.append("e2e")
        suffix = "  · " + " · ".join(tags) if tags else ""
        return f"{name}  —  relay · {url} · {room}{suffix}"
    elif mode == "host":
        return f"{name}  —  host · port {c.get('port', 7331)}"
    elif mode == "connect":
        return f"{name}  —  connect · {c.get('ip', '?')}:{c.get('port', 7331)}"
    return name
