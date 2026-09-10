from fastapi import APIRouter, HTTPException, Depends
from app.database import db
from app.auth import get_current_user, require_role
from bson import ObjectId
from datetime import datetime
from pymongo import DESCENDING

router = APIRouter()


# ─── Get global stats (public) ───
@router.get("/api/stats/counts")
async def get_stats():
    stats = await db.stats.find_one({"_id": "counts"})
    if not stats:
        return {"users": 0, "vendors": 0, "products": 0}

    return {
        "users": stats.get("users", 0),
        "vendors": stats.get("vendors", 0),
        "products": stats.get("products", 0),
    }


# ─── Increment stats (internal/auth) ───
@router.post("/api/stats/increment")
async def increment_stat(data: dict, current_user: dict = Depends(require_role("admin"))):
    field = data.get("field", "")
    amount = data.get("amount", 1)

    if field not in ("users", "vendors", "products"):
        raise HTTPException(400, "Champ invalide")

    from pymongo import UpdateOne
    await db.stats.update_one(
        {"_id": "counts"},
        {"$inc": {field: amount}},
        upsert=True,
    )

    return {"message": f"{field} incrémenté de {amount}"}


# ─── Notifications: list ───
@router.get("/api/notifications")
async def list_notifications(
    current_user: dict = Depends(get_current_user),
):
    uid = current_user["sub"]
    cursor = db.notifications.find({"userId": uid}).sort("createdAt", -1).limit(50)

    notifs = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        notifs.append(doc)

    count_doc = await db.notification_counts.find_one({"_id": uid})
    unread = count_doc.get("unread", 0) if count_doc else 0

    return {"notifications": notifs, "unread": unread}


# ─── Notifications: mark read ───
@router.post("/api/notifications/read")
async def mark_notifications_read(current_user: dict = Depends(get_current_user)):
    uid = current_user["sub"]
    await db.notifications.update_many(
        {"userId": uid, "read": False},
        {"$set": {"read": True}},
    )
    await db.notification_counts.update_one(
        {"_id": uid},
        {"$set": {"unread": 0}},
    )
    return {"message": "Notifications marquées comme lues"}


# ─── Notifications: save (internal) ───
async def save_notification(user_id: str, notif_data: dict):
    from pymongo import UpdateOne
    notif_data["userId"] = user_id
    notif_data["createdAt"] = datetime.utcnow()
    notif_data["read"] = False
    await db.notifications.insert_one(notif_data)
    await db.notification_counts.update_one(
        {"_id": user_id},
        {"$inc": {"unread": 1}},
        upsert=True,
    )


# ─── Vendor stats ───
@router.get("/api/vendors/{vendor_id}/stats")
async def vendor_stats(vendor_id: str, current_user: dict = Depends(require_role("vendeur", "admin"))):
    pipeline = [
        {"$match": {"vendeur_id": vendor_id}},
        {"$group": {
            "_id": None,
            "total_products": {"$sum": 1},
            "total_sales": {"$sum": "$salesCount"},
            "total_revenue": {"$sum": {"$multiply": ["$price", "$salesCount"]}},
        }},
    ]
    result = await db.products.aggregate(pipeline).to_list(1)
    if not result:
        return {"total_products": 0, "total_sales": 0, "total_revenue": 0}

    stats = result[0]
    return {
        "total_products": stats.get("total_products", 0),
        "total_sales": stats.get("total_sales", 0),
        "total_revenue": round(stats.get("total_revenue", 0), 2),
    }
