from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form
from app.database import db
from app.auth import get_current_user, require_role
from bson import ObjectId
from datetime import datetime
import os, shutil

router = APIRouter()

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads", "publicites")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/webm"}
MAX_SIZE = 20 * 1024 * 1024  # 20 MB


def _serialize(doc):
    if doc and "_id" in doc:
        doc["_id"] = str(doc["_id"])
    return doc


# ─── List active publicites (public) ───
@router.get("/api/publicites")
async def list_active_publicites():
    cursor = db.publicites.find({"active": True}).sort("createdAt", -1).limit(20)
    return [_serialize(doc) async for doc in cursor]


# ─── List all publicites (admin) ───
@router.get("/api/publicites/all")
async def list_all_publicites(current_user: dict = Depends(require_role("admin"))):
    cursor = db.publicites.find({}).sort("createdAt", -1)
    return [_serialize(doc) async for doc in cursor]


# ─── Create publicite (admin) ───
@router.post("/api/publicites")
async def create_publicite(
    titre: str = Form(...),
    description: str = Form(""),
    type: str = Form("banner"),
    active: bool = Form(True),
    media: UploadFile = File(None),
    current_user: dict = Depends(require_role("admin")),
):
    media_url = ""
    if media and media.filename:
        if media.content_type not in ALLOWED_TYPES:
            raise HTTPException(400, f"Type non autorisé: {media.content_type}")
        contents = await media.read()
        if len(contents) > MAX_SIZE:
            raise HTTPException(400, "Fichier dépasse 20 Mo")
        ext = os.path.splitext(media.filename)[1] or ".jpg"
        name = f"pub_{datetime.utcnow().timestamp()}{ext}"
        path = os.path.join(UPLOAD_DIR, name)
        with open(path, "wb") as f:
            f.write(contents)
        media_url = f"/uploads/publicites/{name}"

    doc = {
        "titre": titre.strip(),
        "description": description.strip(),
        "type": type,
        "mediaUrl": media_url,
        "active": active,
        "createdAt": datetime.utcnow(),
        "createdBy": current_user["sub"],
    }
    result = await db.publicites.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return doc


# ─── Toggle active ───
@router.put("/api/publicites/{pub_id}")
async def toggle_publicite(pub_id: str, data: dict, current_user: dict = Depends(require_role("admin"))):
    if not ObjectId.is_valid(pub_id):
        raise HTTPException(400, "ID invalide")

    doc = await db.publicites.find_one({"_id": ObjectId(pub_id)})
    if not doc:
        raise HTTPException(404, "Publicité non trouvée")

    updates = {}
    if "active" in data:
        updates["active"] = bool(data["active"])
    if "titre" in data:
        updates["titre"] = data["titre"]
    if "description" in data:
        updates["description"] = data["description"]

    if updates:
        await db.publicites.update_one({"_id": ObjectId(pub_id)}, {"$set": updates})

    return {"message": "Publicité mise à jour"}


# ─── Delete publicite ───
@router.delete("/api/publicites/{pub_id}")
async def delete_publicite(pub_id: str, current_user: dict = Depends(require_role("admin"))):
    if not ObjectId.is_valid(pub_id):
        raise HTTPException(400, "ID invalide")

    doc = await db.publicites.find_one({"_id": ObjectId(pub_id)})
    if not doc:
        raise HTTPException(404, "Publicité non trouvée")

    # Delete media file
    if doc.get("mediaUrl"):
        filepath = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), doc["mediaUrl"].lstrip("/"))
        if os.path.exists(filepath):
            os.remove(filepath)

    await db.publicites.delete_one({"_id": ObjectId(pub_id)})
    return {"message": "Publicité supprimée"}
