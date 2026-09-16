from fastapi import APIRouter, HTTPException, Depends, Header
from app.database import db
from app.auth import require_role
from datetime import datetime
import os

router = APIRouter()

ADMIN_SECRET = os.getenv("ADMIN_SECRET", "aisy-admin-2026-prod")


async def verify_admin(x_admin_token: str = Header(None, alias="X-Admin-Token")):
    if not x_admin_token or x_admin_token != ADMIN_SECRET:
        raise HTTPException(403, "Accès admin interdit")
    return True


VENDORS = [
    {"company_name": "TechStore Pro", "full_name": "Jean Mukendi", "email": "techstore@aisy.com", "phone": "+243811111111", "commune": "Gombe", "localisation": "Kinshasa, Gombe", "latitude": -4.309, "longitude": 15.315, "products_count": 5, "rating": 4.8, "plan": "premium", "subscription_status": "active", "verified": True, "photo": "https://images.unsplash.com/photo-1560250097-0b93528c311a?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "FashionHub", "full_name": "Marie Kabongo", "email": "fashion@aisy.com", "phone": "+243822222222", "commune": "Ngaliema", "localisation": "Kinshasa, Ngaliema", "latitude": -4.341, "longitude": 15.261, "products_count": 3, "rating": 4.3, "plan": "premium", "subscription_status": "active", "verified": True, "photo": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "Maison & Deco", "full_name": "Pierre Tshilombo", "email": "deco@aisy.com", "phone": "+243833333333", "commune": "Limete", "localisation": "Kinshasa, Limete", "latitude": -4.363, "longitude": 15.345, "products_count": 2, "rating": 4.5, "plan": "free", "subscription_status": "active", "verified": False, "photo": "https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "ElectroDiscount", "full_name": "David Kasongo", "email": "electro@aisy.com", "phone": "+243844444444", "commune": "Kalamu", "localisation": "Kinshasa, Kalamu", "latitude": -4.331, "longitude": 15.320, "products_count": 8, "rating": 4.1, "plan": "free", "subscription_status": "active", "verified": False, "photo": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "Bio Market", "full_name": "Grace Lukusa", "email": "bio@aisy.com", "phone": "+243855555555", "commune": "Bandal", "localisation": "Kinshasa, Bandalungwa", "latitude": -4.321, "longitude": 15.290, "products_count": 6, "rating": 4.6, "plan": "premium", "subscription_status": "active", "verified": True, "photo": "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "Casa Electronics", "full_name": "Samuel Kalala", "email": "casa@aisy.com", "phone": "+243866666666", "commune": "Matete", "localisation": "Kinshasa, Matete", "latitude": -4.338, "longitude": 15.305, "products_count": 12, "rating": 4.7, "plan": "premium", "subscription_status": "active", "verified": True, "photo": "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=200&h=200&fit=crop", "role": "vendeur"},
    {"company_name": "Mode Africa", "full_name": "Chantal Mbuyi", "email": "modeafrica@aisy.com", "phone": "+243877777777", "commune": "Barumbu", "localisation": "Kinshasa, Barumbu", "latitude": -4.315, "longitude": 15.328, "products_count": 15, "rating": 4.9, "plan": "premium", "subscription_status": "active", "verified": True, "photo": "https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=200&h=200&fit=crop", "role": "vendeur"},
]


@router.post("/api/admin/seed-vendors")
async def seed_vendors(admin: dict = Depends(require_role("admin")), _token: bool = Depends(verify_admin)):
    if db is None:
        return {"error": "MongoDB non disponible"}
    count = 0
    for v in VENDORS:
        v["created_at"] = datetime.utcnow()
        existing = await db.vendeurs.find_one({"email": v["email"]})
        if not existing:
            await db.vendeurs.insert_one(v)
            count += 1
    total = await db.vendeurs.count_documents({})
    return {"message": f"{count} ajoutes, {total} total dans MongoDB"}


@router.get("/api/admin/seed-vendors")
async def seed_vendors_get(_token: bool = Depends(verify_admin)):
    return await seed_vendors()
