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
