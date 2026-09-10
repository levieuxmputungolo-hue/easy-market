from fastapi import APIRouter, HTTPException, Depends, Query
from app.database import db
from app.auth import get_current_user
from bson import ObjectId
from datetime import datetime
import math

router = APIRouter()


def _serialize(doc):
    if doc and "_id" in doc:
        doc["_id"] = str(doc["_id"])
    return doc


# ─── List conversations (buyer or seller) ───
@router.get("/api/chats")
async def list_chats(
    role: str = Query("buyer", regex="^(buyer|seller)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    uid = current_user["sub"]
    query = {"buyer_id": uid} if role == "buyer" else {"seller_id": uid}

    total = await db.chats.count_documents(query)
    skip = (page - 1) * limit
    cursor = db.chats.find(query).sort("updatedAt", -1).skip(skip).limit(limit)

    chats = []
    async for doc in cursor:
        chats.append(_serialize(doc))

    return {"chats": chats, "total": total, "page": page, "pages": math.ceil(total / limit)}


# ─── Get single conversation ───
@router.get("/api/chats/{chat_id}")
async def get_chat(chat_id: str, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(chat_id):
        raise HTTPException(400, "ID invalide")

    doc = await db.chats.find_one({"_id": ObjectId(chat_id)})
    if not doc:
        raise HTTPException(404, "Conversation non trouvée")

    uid = current_user["sub"]
    if uid not in (doc.get("buyer_id"), doc.get("seller_id"), doc.get("participants", [])):
        raise HTTPException(403, "Accès interdit")

    return _serialize(doc)


# ─── Create new conversation ───
@router.post("/api/chats")
async def create_chat(data: dict, current_user: dict = Depends(get_current_user)):
    uid = current_user["sub"]
    seller_id = data.get("seller_id", "")
    product_id = data.get("product_id", "")
    product_name = data.get("product_name", "")
    product_img = data.get("product_img", "")
    first_message = data.get("first_message", "")

    if not seller_id:
        raise HTTPException(400, "seller_id requis")

    # Check if conversation already exists between buyer and seller for this product
    existing = await db.chats.find_one({
        "buyer_id": uid,
        "seller_id": seller_id,
        "product_id": product_id,
    })
    if existing:
        return _serialize(existing)

    now = datetime.utcnow()
    chat = {
        "buyer_id": uid,
        "seller_id": seller_id,
        "participants": [uid, seller_id],
        "product_id": product_id,
        "product_name": product_name,
        "product_img": product_img,
        "lastMessage": first_message or "",
        "lastSenderId": uid if first_message else "",
        "unread_buyer": 0,
        "unread_seller": 1 if first_message else 0,
        "createdAt": now,
        "updatedAt": now,
    }
    result = await db.chats.insert_one(chat)
    chat["_id"] = str(result.inserted_id)

    # Send first message if provided
    if first_message:
        msg = {
            "chatId": str(result.inserted_id),
            "senderId": uid,
            "senderName": current_user.get("name", ""),
            "senderRole": "buyer",
            "text": first_message,
            "type": "text",
            "timestamp": now,
            "read": False,
        }
        await db.messages.insert_one(msg)

    return chat


# ─── Get messages (paginated) ───
@router.get("/api/chats/{chat_id}/messages")
async def get_messages(
    chat_id: str,
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    current_user: dict = Depends(get_current_user),
):
    if not ObjectId.is_valid(chat_id):
        raise HTTPException(400, "ID invalide")

    chat = await db.chats.find_one({"_id": ObjectId(chat_id)})
    if not chat:
        raise HTTPException(404, "Conversation non trouvée")

    uid = current_user["sub"]
    if uid not in (chat.get("buyer_id"), chat.get("seller_id"), chat.get("participants", [])):
        raise HTTPException(403, "Accès interdit")

    total = await db.messages.count_documents({"chatId": chat_id})
    skip = (page - 1) * limit
    cursor = db.messages.find({"chatId": chat_id}).sort("timestamp", -1).skip(skip).limit(limit)

    messages = []
    async for doc in cursor:
        messages.append(_serialize(doc))

    messages.reverse()  # oldest first

    return {"messages": messages, "total": total, "page": page, "pages": math.ceil(total / limit)}


# ─── Send message ───
@router.post("/api/chats/{chat_id}/messages")
async def send_message(chat_id: str, data: dict, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(chat_id):
        raise HTTPException(400, "ID invalide")

    chat = await db.chats.find_one({"_id": ObjectId(chat_id)})
    if not chat:
        raise HTTPException(404, "Conversation non trouvée")

    uid = current_user["sub"]
    if uid not in (chat.get("buyer_id"), chat.get("seller_id"), chat.get("participants", [])):
        raise HTTPException(403, "Accès interdit")

    text = data.get("text", "")
    msg_type = data.get("type", "text")
    extra = data.get("extra", {})

    if not text and msg_type == "text":
        raise HTTPException(400, "Le message ne peut pas être vide")

    now = datetime.utcnow()
    sender_role = "buyer" if uid == chat.get("buyer_id") else "seller"

    msg = {
        "chatId": chat_id,
        "senderId": uid,
        "senderName": current_user.get("name", ""),
        "senderRole": sender_role,
        "text": text,
        "type": msg_type,
        "timestamp": now,
        "read": False,
    }
    msg.update(extra)

    result = await db.messages.insert_one(msg)
    msg["_id"] = str(result.inserted_id)

    # Update chat
    unread_field = "unread_seller" if sender_role == "buyer" else "unread_buyer"
    await db.chats.update_one(
        {"_id": ObjectId(chat_id)},
        {
            "$set": {
                "lastMessage": text[:200] if text else f"[{msg_type}]",
                "lastSenderId": uid,
                "updatedAt": now,
            },
            "$inc": {unread_field: 1},
        },
    )

    return msg


# ─── Mark messages as read ───
@router.post("/api/chats/{chat_id}/read")
async def mark_read(chat_id: str, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(chat_id):
        raise HTTPException(400, "ID invalide")

    chat = await db.chats.find_one({"_id": ObjectId(chat_id)})
    if not chat:
        raise HTTPException(404, "Conversation non trouvée")

    uid = current_user["sub"]
    sender_role = "buyer" if uid == chat.get("buyer_id") else "seller"
    unread_field = "unread_seller" if sender_role == "buyer" else "unread_buyer"

    await db.messages.update_many(
        {"chatId": chat_id, "senderId": {"$ne": uid}, "read": False},
        {"$set": {"read": True}},
    )
    await db.chats.update_one(
        {"_id": ObjectId(chat_id)},
        {"$set": {unread_field: 0}},
    )

    return {"message": "Messages marqués comme lus"}


# ─── Update chat (settings, lastLocation, etc.) ───
@router.put("/api/chats/{chat_id}")
async def update_chat(chat_id: str, data: dict, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(chat_id):
        raise HTTPException(400, "ID invalide")

    chat = await db.chats.find_one({"_id": ObjectId(chat_id)})
    if not chat:
        raise HTTPException(404, "Conversation non trouvée")

    uid = current_user["sub"]
    if uid not in (chat.get("buyer_id"), chat.get("seller_id"), chat.get("participants", [])):
        raise HTTPException(403, "Accès interdit")

    allowed_fields = ["lastLocation", "quotation", "orderStatus"]
    updates = {}
    for field in allowed_fields:
        if field in data:
            updates[field] = data[field]
    updates["updatedAt"] = datetime.utcnow()

    await db.chats.update_one({"_id": ObjectId(chat_id)}, {"$set": updates})
    return {"message": "Conversation mise à jour"}
