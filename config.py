import json
from pathlib import Path

_CONFIG_FILE = Path.home() / ".rootchat" / "config.json"


def load_username() -> str | None:
    if _CONFIG_FILE.exists():
        return json.loads(_CONFIG_FILE.read_text()).get("username")
    return None


def save_username(username: str) -> None:
    _CONFIG_FILE.parent.mkdir(exist_ok=True)
    _CONFIG_FILE.write_text(json.dumps({"username": username}))
