from __future__ import annotations

from datetime import datetime
from pathlib import Path


class History:
    _LOG_DIR = Path.home() / ".rootchat" / "logs"

    def __init__(self, peer_addr: str) -> None:
        self._LOG_DIR.mkdir(parents=True, exist_ok=True)
        import re
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M")
        safe_peer = re.sub(r"[^a-zA-Z0-9._-]+", "-", peer_addr).strip("-")
        path = self._LOG_DIR / f"{ts}_{safe_peer}.log"
        self._fh = path.open("a", encoding="utf-8", buffering=1)

    def log(self, ts: str, user: str, text: str) -> None:
        self._fh.write(f"[{ts}] {user}: {text}\n")

    def log_system(self, msg: str) -> None:
        ts = datetime.now().strftime("%H:%M")
        self._fh.write(f"[{ts}] · {msg}\n")

    def close(self) -> None:
        self._fh.close()
