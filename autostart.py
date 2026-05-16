from __future__ import annotations

import sys
from pathlib import Path

_APP_NAME = "rootchat"
_REG_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
_DESKTOP_FILE = Path.home() / ".config" / "autostart" / "rootchat.desktop"


def _is_windows() -> bool:
    return sys.platform == "win32"


def _exec_cmd() -> str:
    exe = sys.executable
    # Running as a PyInstaller bundle: sys.frozen is set
    if getattr(sys, "frozen", False):
        return f'"{exe}" --autoconnect'
    # Running from source: invoke the same Python with main.py
    main = Path(sys.argv[0]).resolve()
    return f'"{exe}" "{main}" --autoconnect'


def is_enabled() -> bool:
    if _is_windows():
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _REG_KEY, 0, winreg.KEY_READ)
            winreg.QueryValueEx(key, _APP_NAME)
            winreg.CloseKey(key)
            return True
        except (FileNotFoundError, OSError):
            return False
    else:
        return _DESKTOP_FILE.exists()


def enable() -> None:
    if _is_windows():
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _REG_KEY, 0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(key, _APP_NAME, 0, winreg.REG_SZ, _exec_cmd())
        winreg.CloseKey(key)
    else:
        _DESKTOP_FILE.parent.mkdir(parents=True, exist_ok=True)
        _DESKTOP_FILE.write_text(
            "[Desktop Entry]\n"
            "Type=Application\n"
            f"Name={_APP_NAME}\n"
            f"Exec={_exec_cmd()}\n"
            "Hidden=false\n"
            "NoDisplay=false\n"
            "X-GNOME-Autostart-enabled=true\n"
        )


def disable() -> None:
    if _is_windows():
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, _REG_KEY, 0, winreg.KEY_SET_VALUE)
            winreg.DeleteValue(key, _APP_NAME)
            winreg.CloseKey(key)
        except (FileNotFoundError, OSError):
            pass
    else:
        try:
            _DESKTOP_FILE.unlink()
        except FileNotFoundError:
            pass
