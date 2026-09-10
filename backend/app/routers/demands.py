from fastapi import APIRouter, HTTPException, Depends, Query
from app.database import db
from app.auth import get_current_user, require_role
from bson import ObjectId
from datetime import datetime
from collections import Counter
import math

router = APIRouter()


# ─── Log a search demand ───
@router.post("/api/demands")
async def create_demand(data: dict):
    query_text = data.get("query", "").strip()
    if not query_text:
        raise HTTPException(400, "query requis")

    existing = await db.demands.find_one({"query": query_text.lower()})
    if existing:
        await db.demands.update_one(
            {"_id": existing["_id"]},
            {"$inc": {"count": 1}, "$set": {"last": datetime.utcnow()}},
        )
    else:
        await db.demands.insert_one({
            "query": query_text.lower(),
            "count": 1,
            "first": datetime.utcnow(),
            "last": datetime.utcnow(),
        })

    return {"message": "Demande enregistrée"}


# ─── List demands (vendor dashboard) ───
@router.get("/api/demands")
async def list_demands(
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
    current_user: dict = Depends(get_current_user),
):
    total = await db.demands.count_documents({})
    skip = (page - 1) * limit
    cursor = db.demands.find({}).sort("count", -1).skip(skip).limit(limit)

    demands = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        demands.append(doc)

    return {"demands": demands, "total": total, "page": page, "pages": math.ceil(total / limit)}
