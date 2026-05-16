from __future__ import annotations

import json
import logging
import os
from collections import defaultdict
from datetime import datetime

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

load_dotenv()

RELAY_API_KEY = os.getenv("RELAY_API_KEY", "")

app = FastAPI()

logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger(__name__)

if RELAY_API_KEY:
    log.info("relay auth enabled")
else:
    log.warning("RELAY_API_KEY not set — relay is open, anyone can connect")

# room -> list of (username, websocket)
rooms: dict[str, list[tuple[str, WebSocket]]] = defaultdict(list)


@app.get("/health")
async def health() -> JSONResponse:
    room_info = {room: [u for u, _ in clients] for room, clients in rooms.items()}
    return JSONResponse({"status": "ok", "rooms": room_info})


@app.websocket("/ws")
async def ws_endpoint(
    websocket: WebSocket,
    username: str = "anonymous",
    room: str = "default",
) -> None:
    if RELAY_API_KEY:
        auth = websocket.headers.get("authorization", "")
        if auth != f"Bearer {RELAY_API_KEY}":
            await websocket.close(code=1008)
            log.warning(f"rejected {websocket.client} — invalid API key")
            return
    await websocket.accept()
    # Close any stale connections for this username in the room
    stale = [ws for u, ws in rooms[room] if u == username]
    for ws in stale:
        try:
            await ws.close()
        except Exception:
            pass
    rooms[room] = [(u, ws) for u, ws in rooms[room] if u != username]
    rooms[room].append((username, websocket))
    log.info(f"{username} joined [{room}]  ({len(rooms[room])} in room)")

    await _broadcast(room, websocket, _system_msg(f"{username} joined"))

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            to_user = msg.get("to")
            if to_user:
                await _send_dm(room, websocket, msg, to_user)
            else:
                await _broadcast(room, websocket, msg)
    except WebSocketDisconnect:
        pass
    finally:
        rooms[room] = [(u, ws) for u, ws in rooms[room] if ws is not websocket]
        if not rooms[room]:
            del rooms[room]
        log.info(f"{username} left [{room}]")
        await _broadcast(room, None, _system_msg(f"{username} left"))


async def _broadcast(room: str, sender: WebSocket | None, msg: dict) -> None:
    data = json.dumps(msg)
    dead: list[WebSocket] = []
    for _, ws in list(rooms.get(room, [])):
        if ws is not sender:
            try:
                await ws.send_text(data)
            except Exception:
                dead.append(ws)
    if dead:
        rooms[room] = [(u, ws) for u, ws in rooms.get(room, []) if ws not in dead]


async def _send_dm(room: str, sender: WebSocket, msg: dict, to_user: str) -> None:
    data = json.dumps(msg)
    for uname, ws in list(rooms.get(room, [])):
        if ws is not sender and uname == to_user:
            try:
                await ws.send_text(data)
            except Exception:
                pass
            return
    log.info(f"DM to {to_user!r} not delivered — not in room")


def _system_msg(text: str) -> dict:
    return {"user": "·", "text": text, "ts": datetime.now().strftime("%H:%M")}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7332)
