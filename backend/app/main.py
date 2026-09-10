from fastapi import FastAPI, Request, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.database import init_db, db
from app.auth import decode_token
from app.routers import products, users, orders, sellers, vendeurs, payments, chats, publicites, demands, notifications
import os
import socketio

# ─── Socket.IO (real-time) ───
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",
    logger=False,
    engineio_logger=False,
)

app = FastAPI(title="Easy Market API")

# ─── CORS ───
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8000",
        "https://easy-market-96c4a.web.app",
        "https://easy-market-96c4a.firebaseapp.com",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

# ─── Routers ───
app.include_router(products.router)
app.include_router(users.router)
app.include_router(orders.router)
app.include_router(sellers.router)
app.include_router(vendeurs.router)
app.include_router(payments.router)
app.include_router(chats.router)
app.include_router(publicites.router)
app.include_router(demands.router)
app.include_router(notifications.router)

# ─── Static files ───
WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "web")
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads")
if os.path.isdir(UPLOAD_DIR):
    app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")
if os.path.isdir(WEB_DIR):
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")


# ─── Security middleware ───
@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    if request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
    return response


@app.middleware("http")
async def protect_uploads_middleware(request: Request, call_next):
    if request.url.path.startswith("/uploads/"):
        token = request.cookies.get("access_token") or request.headers.get("Authorization", "").replace("Bearer ", "")
        if not token or not decode_token(token):
            return JSONResponse(status_code=403, content={"detail": "Authentification requise"})
    return await call_next(request)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
    )


# ─── Startup ───
@app.on_event("startup")
async def startup():
    await init_db()


# ═══════════════════════════════════════════════
# SOCKET.IO EVENTS — Real-time messaging
# ═══════════════════════════════════════════════

@sio.event
async def connect(sid, environ, auth):
    """Authenticate socket connection with JWT token."""
    token = None
    if auth and isinstance(auth, dict):
        token = auth.get("token")

    if not token:
        raise socketio.exceptions.ConnectionRefusedError("Authentification requise")

    try:
        payload = decode_token(token)
    except Exception:
        raise socketio.exceptions.ConnectionRefusedError("Token invalide")

    user_id = payload.get("sub")
    user_role = payload.get("role", "client")
    user_name = payload.get("name", "")

    # Store user info in session
    await sio.save_session(sid, {
        "user_id": user_id,
        "role": user_role,
        "name": user_name,
    })

    # Join personal room
    await sio.enter_room(sid, f"user:{user_id}")
    print(f"[WS] {user_name} ({user_role}) connecté — sid={sid}")


@sio.event
async def disconnect(sid):
    session = await sio.get_session(sid)
    if session:
        user_id = session.get("user_id", "")
        if user_id:
            await sio.leave_room(sid, f"user:{user_id}")
        print(f"[WS] {session.get('name', '?')} déconnecté")


@sio.event
async def chat_join(sid, data):
    """Join a chat room for real-time updates."""
    chat_id = data.get("chat_id", "")
    if not chat_id:
        return

    session = await sio.get_session(sid)
    user_id = session.get("user_id", "")

    # Verify user is participant
    chat = await db.chats.find_one({"_id": __import__("bson").ObjectId(chat_id)})
    if not chat:
        return

    if user_id in (chat.get("buyer_id"), chat.get("seller_id")) or user_id in chat.get("participants", []):
        await sio.enter_room(sid, f"chat:{chat_id}")
        print(f"[WS] {session.get('name')} a rejoint le chat {chat_id}")


@sio.event
async def chat_leave(sid, data):
    """Leave a chat room."""
    chat_id = data.get("chat_id", "")
    if chat_id:
        await sio.leave_room(sid, f"chat:{chat_id}")


@sio.event
async def chat_send_message(sid, data):
    """Send a message via WebSocket."""
    session = await sio.get_session(sid)
    user_id = session.get("user_id", "")
    user_name = session.get("name", "")
    user_role = session.get("role", "client")

    chat_id = data.get("chat_id", "")
    text = data.get("text", "")
    msg_type = data.get("type", "text")
    extra = data.get("extra", {})

    if not chat_id or not text:
        return

    chat = await db.chats.find_one({"_id": __import__("bson").ObjectId(chat_id)})
    if not chat:
        return

    if user_id not in (chat.get("buyer_id"), chat.get("seller_id"), *chat.get("participants", [])):
        return

    from datetime import datetime
    now = datetime.utcnow()
    sender_role = "buyer" if user_id == chat.get("buyer_id") else "seller"

    msg = {
        "chatId": chat_id,
        "senderId": user_id,
        "senderName": user_name,
        "senderRole": sender_role,
        "text": text,
        "type": msg_type,
        "timestamp": now,
        "read": False,
    }
    msg.update(extra)

    result = await db.messages.insert_one(msg)
    msg_id = str(result.inserted_id)
    msg["_id"] = msg_id

    # Update chat
    unread_field = "unread_seller" if sender_role == "buyer" else "unread_buyer"
    await db.chats.update_one(
        {"_id": __import__("bson").ObjectId(chat_id)},
        {
            "$set": {
                "lastMessage": text[:200] if text else f"[{msg_type}]",
                "lastSenderId": user_id,
                "updatedAt": now,
            },
            "$inc": {unread_field: 1},
        },
    )

    # Broadcast to chat room
    await sio.emit("chat:new_message", msg, room=f"chat:{chat_id}")

    # Notify other user via their personal room
    other_id = chat.get("buyer_id") if user_id == chat.get("seller_id") else chat.get("seller_id")
    if other_id:
        await sio.emit("chat:conversation_update", {
            "chatId": chat_id,
            "lastMessage": text[:200] if text else f"[{msg_type}]",
            "lastSenderId": user_id,
            "updatedAt": now.isoformat(),
        }, room=f"user:{other_id}")


@sio.event
async def chat_typing_start(sid, data):
    """Broadcast typing indicator."""
    session = await sio.get_session(sid)
    chat_id = data.get("chat_id", "")
    if chat_id:
        await sio.emit("chat:typing", {
            "chatId": chat_id,
            "userId": session.get("user_id"),
            "userName": session.get("name"),
            "typing": True,
        }, room=f"chat:{chat_id}", skip_sid=sid)


@sio.event
async def chat_typing_stop(sid, data):
    """Stop typing indicator."""
    session = await sio.get_session(sid)
    chat_id = data.get("chat_id", "")
    if chat_id:
        await sio.emit("chat:typing", {
            "chatId": chat_id,
            "userId": session.get("user_id"),
            "typing": False,
        }, room=f"chat:{chat_id}", skip_sid=sid)


@sio.event
async def chat_mark_read(sid, data):
    """Mark messages as read via WebSocket."""
    session = await sio.get_session(sid)
    user_id = session.get("user_id", "")
    chat_id = data.get("chat_id", "")

    if not chat_id:
        return

    chat = await db.chats.find_one({"_id": __import__("bson").ObjectId(chat_id)})
    if not chat:
        return

    sender_role = "buyer" if user_id == chat.get("buyer_id") else "seller"
    unread_field = "unread_seller" if sender_role == "buyer" else "unread_buyer"

    await db.messages.update_many(
        {"chatId": chat_id, "senderId": {"$ne": user_id}, "read": False},
        {"$set": {"read": True}},
    )
    await db.chats.update_one(
        {"_id": __import__("bson").ObjectId(chat_id)},
        {"$set": {unread_field: 0}},
    )

    # Broadcast read receipt
    await sio.emit("chat:read_receipt", {
        "chatId": chat_id,
        "readBy": user_id,
    }, room=f"chat:{chat_id}")


# ─── ASGI app (Socket.IO + FastAPI) ───
socket_app = socketio.ASGIApp(sio, app)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:socket_app", host="0.0.0.0", port=8000, reload=True)
