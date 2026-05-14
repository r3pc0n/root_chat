from __future__ import annotations

import json
import logging
from collections import defaultdict
from datetime import datetime

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

app = FastAPI()

logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger(__name__)

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
    await websocket.accept()
    rooms[room].append((username, websocket))
    log.info(f"{username} joined [{room}]  ({len(rooms[room])} in room)")

    await _broadcast(room, websocket, _system_msg(f"{username} joined"))

    try:
        while True:
            data = await websocket.receive_text()
            await _broadcast(room, websocket, json.loads(data))
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
    for _, ws in list(rooms.get(room, [])):
        if ws is not sender:
            try:
                await ws.send_text(data)
            except Exception:
                pass


def _system_msg(text: str) -> dict:
    return {"user": "·", "text": text, "ts": datetime.now().strftime("%H:%M")}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7332)
