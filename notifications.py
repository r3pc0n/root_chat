from __future__ import annotations

import base64
import subprocess
import sys

_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def notify(title: str, body: str) -> None:
    try:
        if sys.platform == "win32":
            _notify_windows(title, body)
        else:
            _notify_linux(title, body)
    except Exception:
        pass


def _notify_windows(title: str, body: str) -> None:
    t = title.replace("'", "''")
    b = body.replace("'", "''").replace("\n", " ")[:120]
    script = f"""
[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]|Out-Null
$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent('ToastText02')
$xml.GetElementsByTagName('text')[0].InnerText='{t}'
$xml.GetElementsByTagName('text')[1].InnerText='{b}'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Root Chat').Show([Windows.UI.Notifications.ToastNotification]::new($xml))
"""
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    subprocess.Popen(
        ["powershell", "-WindowStyle", "Hidden", "-NonInteractive", "-EncodedCommand", encoded],
        creationflags=_NO_WINDOW,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _notify_linux(title: str, body: str) -> None:
    subprocess.Popen(
        ["notify-send", "-a", "Root Chat", "-t", "4000", title, body[:120]],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
