from fastapi import APIRouter, HTTPException, Depends
from app.database import db
from app.auth import get_current_user
from bson import ObjectId
from datetime import datetime

router = APIRouter()

@router.post("/api/orders")
async def create_order(data: dict, current_user: dict = Depends(get_current_user)):
    user_id = current_user["sub"]
    items = data.get("items", [])
    total = data.get("total", 0)
    if not items:
        raise HTTPException(400, "items requis")
    doc = {
        "user_id": user_id,
        "items": items,
        "total": total,
        "status": "pending",
        "created_at": datetime.utcnow(),
    }
    result = await db.orders.insert_one(doc)
    return {"_id": str(result.inserted_id), **doc}

@router.get("/api/orders/{user_id}")
async def get_orders(user_id: str, current_user: dict = Depends(get_current_user)):
    if current_user["sub"] != user_id and current_user.get("role") != "admin":
        raise HTTPException(403, "Accès interdit - vous ne pouvez voir que vos propres commandes")
    cursor = db.orders.find({"user_id": user_id}).sort("created_at", -1)
    orders = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        orders.append(doc)
    return orders
