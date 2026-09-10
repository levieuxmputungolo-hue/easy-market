from fastapi import APIRouter, HTTPException, Depends, Query
from app.database import db
from app.auth import get_current_user, require_role
from bson import ObjectId
from datetime import datetime
import math

router = APIRouter()


@router.post("/api/orders")
async def create_order(data: dict, current_user: dict = Depends(get_current_user)):
    user_id = current_user["sub"]
    items = data.get("items", [])
    total = data.get("total", 0)
    if not items or not isinstance(items, list) or len(items) == 0:
        raise HTTPException(400, "items requis et doit être une liste non vide")
    for item in items:
        if not isinstance(item, dict) or "product_id" not in item or "quantity" not in item:
            raise HTTPException(400, "Chaque item doit contenir product_id et quantity")
        if not isinstance(item["quantity"], int) or item["quantity"] <= 0:
            raise HTTPException(400, "La quantité doit être un entier positif")
    try:
        total = float(total)
    except (TypeError, ValueError):
        raise HTTPException(400, "Le total doit être un nombre valide")
    if total <= 0:
        raise HTTPException(400, "Le total doit être supérieur à 0")

    doc = {
        "user_id": user_id,
        "buyer_id": user_id,
        "buyer_name": current_user.get("name", ""),
        "items": items,
        "total": total,
        "status": "pending",
        "created_at": datetime.utcnow(),
    }
    result = await db.orders.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return doc


@router.get("/api/orders/{user_id}")
async def get_orders(user_id: str, current_user: dict = Depends(get_current_user)):
    if current_user["sub"] != user_id and current_user.get("role") != "admin":
        raise HTTPException(403, "Accès interdit - vous ne pouvez voir que vos propres commandes")

    page = int(current_user.get("page", 1))
    limit = 50
    skip = (page - 1) * limit

    total = await db.orders.count_documents({"user_id": user_id})
    cursor = db.orders.find({"user_id": user_id}).sort("created_at", -1).skip(skip).limit(limit)
    orders = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        orders.append(doc)

    return {"orders": orders, "total": total, "page": page, "pages": math.ceil(total / limit)}


# ─── Update order status (seller or admin) ───
@router.put("/api/orders/{order_id}")
async def update_order_status(order_id: str, data: dict, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(order_id):
        raise HTTPException(400, "ID invalide")

    order = await db.orders.find_one({"_id": ObjectId(order_id)})
    if not order:
        raise HTTPException(404, "Commande non trouvée")

    uid = current_user["sub"]
    role = current_user.get("role", "client")
    if role != "admin" and uid != order.get("seller_id") and uid != order.get("user_id"):
        raise HTTPException(403, "Accès interdit")

    new_status = data.get("status", "")
    valid_statuses = ["pending", "preparation", "shipped", "delivered", "cancelled"]
    if new_status not in valid_statuses:
        raise HTTPException(400, f"Statut invalide. Valeurs: {valid_statuses}")

    updates = {"status": new_status, "updatedAt": datetime.utcnow()}
    if "tracking_number" in data:
        updates["tracking_number"] = data["tracking_number"]
    if "delivery_date" in data:
        updates["delivery_date"] = data["delivery_date"]
    if "address" in data:
        updates["address"] = data["address"]

    await db.orders.update_one({"_id": ObjectId(order_id)}, {"$set": updates})

    order["status"] = new_status
    order["_id"] = str(order["_id"])
    return order


# ─── List all orders (admin) ───
@router.get("/api/admin/orders")
async def admin_list_orders(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    status: str = "",
    current_user: dict = Depends(require_role("admin")),
):
    query = {}
    if status:
        query["status"] = status

    total = await db.orders.count_documents(query)
    skip = (page - 1) * limit
    cursor = db.orders.find(query).sort("created_at", -1).skip(skip).limit(limit)

    orders = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        orders.append(doc)

    return {"orders": orders, "total": total, "page": page, "pages": math.ceil(total / limit)}
