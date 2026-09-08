from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Depends, Response
from app.database import db
from app.auth import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, decode_token,
    set_auth_cookies, clear_auth_cookies,
    get_current_user, require_role, has_permission,
    generate_mfa_secret, get_mfa_uri, verify_mfa_code,
)
from datetime import datetime, timedelta
from bson import ObjectId
import os, shutil

router = APIRouter()

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

MAX_ID_CARD_SIZE = 10 * 1024 * 1024  # 10 MB

# ─── Register ───
@router.post("/api/vendeurs/register")
async def register_vendeur(
    full_name: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    phone: str = Form(...),
    activity: str = Form(...),
    company_name: str = Form(...),
    id_card: UploadFile = File(...),
    response: Response = None,
):
    existing = await db.vendeurs.find_one({"email": email})
    if existing:
        raise HTTPException(400, "Email déjà utilisé")

    ext = os.path.splitext(id_card.filename)[1] or ".jpg"
    filename = f"id_{datetime.utcnow().timestamp()}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    contents = await id_card.read()
    if len(contents) > MAX_ID_CARD_SIZE:
        raise HTTPException(400, "La pièce d'identité dépasse 10 Mo")
    with open(filepath, "wb") as f:
        f.write(contents)
    id_card_url = f"/uploads/{filename}"

    now = datetime.utcnow()
    doc = {
        "full_name": full_name,
        "email": email,
        "password": hash_password(password),
        "phone": phone,
        "activity": activity,
        "company_name": company_name,
        "id_card_url": id_card_url,
        "role": "vendeur",
        "subscription_status": "trial",
        "trial_start": now,
        "trial_end": now + timedelta(days=14),
        "subscription_start": None,
        "last_payment": None,
        "mfa_secret": None,
        "mfa_enabled": False,
        "created_at": now,
    }
    result = await db.vendeurs.insert_one(doc)

    payload = {
        "sub": str(result.inserted_id),
        "email": email,
        "name": full_name,
        "company": company_name,
        "role": "vendeur",
        "mfa_required": False,
    }
    access_token = create_access_token(payload)
    refresh_token = create_refresh_token({"sub": str(result.inserted_id)})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {
            "_id": str(result.inserted_id),
            "full_name": full_name,
            "email": email,
            "company_name": company_name,
            "role": "vendeur",
            "subscription_status": "trial",
        },
        "mfa_required": False,
    }

# ─── Login ───
@router.post("/api/vendeurs/login")
async def login_vendeur(data: dict, response: Response):
    email = data.get("email", "")
    password = data.get("password", "")
    v = await db.vendeurs.find_one({"email": email})
    if not v or not verify_password(password, v["password"]):
        import hashlib
        if v and not v.get("password", "").startswith("$2b$"):
            if v["password"] != hashlib.sha256(password.encode()).hexdigest():
                raise HTTPException(401, "Email ou mot de passe incorrect")
        else:
            raise HTTPException(401, "Email ou mot de passe incorrect")

    if v.get("mfa_enabled"):
        temp_token = create_access_token({
            "sub": str(v["_id"]),
            "email": v["email"],
            "name": v.get("full_name", ""),
            "role": "vendeur",
            "mfa_pending": True,
        }, expires_delta=timedelta(minutes=5))
        return {
            "mfa_required": True,
            "mfa_token": temp_token,
            "user": {"email": v["email"]},
        }

    payload = {
        "sub": str(v["_id"]),
        "email": v["email"],
        "name": v.get("full_name", ""),
        "company": v.get("company_name", ""),
        "role": "vendeur",
        "mfa_required": False,
    }
    access_token = create_access_token(payload)
    refresh_token = create_refresh_token({"sub": str(v["_id"])})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {
            "_id": str(v["_id"]),
            "full_name": v.get("full_name", ""),
            "email": v["email"],
            "company_name": v.get("company_name", ""),
            "role": "vendeur",
            "subscription_status": v.get("subscription_status", "trial"),
        },
        "mfa_required": False,
    }

# ─── Vendeur MFA endpoints ───
@router.post("/api/vendeurs/mfa/verify")
async def vendeur_mfa_verify(data: dict, response: Response):
    mfa_token = data.get("mfa_token", "")
    code = data.get("code", "")
    payload = decode_token(mfa_token)
    if not payload.get("mfa_pending"):
        raise HTTPException(400, "Token invalide pour MFA")

    v = await db.vendeurs.find_one({"_id": ObjectId(payload["sub"])})
    if not v or not v.get("mfa_secret"):
        raise HTTPException(400, "MFA non configuré")

    if not verify_mfa_code(v["mfa_secret"], code):
        raise HTTPException(401, "Code MFA invalide")

    final_payload = {
        "sub": str(v["_id"]),
        "email": v["email"],
        "name": v.get("full_name", ""),
        "company": v.get("company_name", ""),
        "role": "vendeur",
        "mfa_required": False,
    }
    access_token = create_access_token(final_payload)
    refresh_token = create_refresh_token({"sub": str(v["_id"])})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {
            "_id": str(v["_id"]),
            "full_name": v.get("full_name", ""),
            "email": v["email"],
            "company_name": v.get("company_name", ""),
            "role": "vendeur",
        },
        "mfa_required": False,
    }

@router.post("/api/vendeurs/mfa/setup")
async def vendeur_mfa_setup(current_user: dict = Depends(get_current_user)):
    v = await db.vendeurs.find_one({"_id": ObjectId(current_user["sub"])})
    if not v:
        raise HTTPException(404, "Vendeur non trouvé")
    secret = generate_mfa_secret()
    uri = get_mfa_uri(secret, v["email"])
    await db.vendeurs.update_one({"_id": ObjectId(current_user["sub"])}, {"$set": {"mfa_pending_secret": secret}})
    return {"secret": secret, "uri": uri}

@router.post("/api/vendeurs/mfa/confirm")
async def vendeur_mfa_confirm(data: dict, current_user: dict = Depends(get_current_user)):
    code = data.get("code", "")
    v = await db.vendeurs.find_one({"_id": ObjectId(current_user["sub"])})
    if not v or not v.get("mfa_pending_secret"):
        raise HTTPException(400, "Configurez d'abord le MFA")
    if not verify_mfa_code(v["mfa_pending_secret"], code):
        raise HTTPException(401, "Code invalide")
    await db.vendeurs.update_one(
        {"_id": ObjectId(current_user["sub"])},
        {"$set": {"mfa_secret": v["mfa_pending_secret"], "mfa_enabled": True},
         "$unset": {"mfa_pending_secret": ""}}
    )
    return {"mfa_enabled": True, "message": "MFA activé avec succès"}

@router.post("/api/vendeurs/mfa/disable")
async def vendeur_mfa_disable(data: dict, current_user: dict = Depends(get_current_user)):
    code = data.get("code", "")
    v = await db.vendeurs.find_one({"_id": ObjectId(current_user["sub"])})
    if not v or not v.get("mfa_secret"):
        raise HTTPException(400, "MFA non configuré")
    if not verify_mfa_code(v["mfa_secret"], code):
        raise HTTPException(401, "Code invalide")
    await db.vendeurs.update_one(
        {"_id": ObjectId(current_user["sub"])},
        {"$set": {"mfa_enabled": False}, "$unset": {"mfa_secret": "", "mfa_pending_secret": ""}}
    )
    return {"mfa_enabled": False, "message": "MFA désactivé"}

# ─── Protected: Vendeur profile (RBAC: only vendeur or admin) ───
@router.get("/api/vendeurs/me")
async def get_vendeur_me(current_user: dict = Depends(require_role("vendeur", "admin"))):
    v = await db.vendeurs.find_one({"_id": ObjectId(current_user["sub"])})
    if not v:
        raise HTTPException(404, "Vendeur non trouvé")
    v["_id"] = str(v["_id"])
    v.pop("password", None)
    v.pop("mfa_secret", None)
    v.pop("mfa_pending_secret", None)
    return v

@router.get("/api/vendeurs/{vendeur_id}")
async def get_vendeur_public(vendeur_id: str):
    v = await db.vendeurs.find_one({"_id": ObjectId(vendeur_id)})
    if not v:
        raise HTTPException(404, "Vendeur non trouvé")
    return {
        "_id": str(v["_id"]),
        "full_name": v.get("full_name", ""),
        "company_name": v.get("company_name", ""),
        "activity": v.get("activity", ""),
        "phone": v.get("phone", ""),
    }

@router.get("/api/vendeurs/{vendeur_id}/status")
async def subscription_status(vendeur_id: str):
    v = await db.vendeurs.find_one({"_id": ObjectId(vendeur_id)})
    if not v:
        raise HTTPException(404, "Vendeur non trouvé")
    now = datetime.utcnow()
    status = v["subscription_status"]
    trial_end = v.get("trial_end")
    if status == "trial" and trial_end and now > trial_end:
        status = "expired"
        await db.vendeurs.update_one({"_id": v["_id"]}, {"$set": {"subscription_status": "expired"}})
    return {
        "status": status,
        "trial_end": trial_end.isoformat() if trial_end else None,
        "message": "Période d'essai active" if status == "trial" else
                   "Abonnement actif" if status == "active" else
                   "Abonnement expiré - Souscrivez pour continuer",
    }

@router.post("/api/vendeurs/subscribe")
async def subscribe(data: dict, current_user: dict = Depends(require_role("vendeur", "admin"))):
    vendeur_id = current_user["sub"]
    months = int(data.get("months", 1))
    amount = 5 * months

    v = await db.vendeurs.find_one({"_id": ObjectId(vendeur_id)})
    if not v:
        raise HTTPException(404, "Vendeur non trouvé")

    now = datetime.utcnow()
    new_expiry = now + timedelta(days=30 * months)

    await db.vendeurs.update_one({"_id": v["_id"]}, {"$set": {
        "subscription_status": "active",
        "subscription_start": now,
        "subscription_end": new_expiry,
        "last_payment": now,
        "plan": "abonnement",
        "commission_rate": 0,
    }})

    return {
        "status": "active",
        "subscription_end": new_expiry.isoformat(),
        "amount": amount,
        "message": f"Abonnement activé pour {months} mois",
    }

# ─── Admin: List all vendeurs (RBAC: admin only) ───
@router.get("/api/admin/vendeurs")
async def admin_list_vendeurs(current_user: dict = Depends(require_role("admin"))):
    cursor = db.vendeurs.find({}, {"password": 0, "mfa_secret": 0, "mfa_pending_secret": 0})
    vendeurs = await cursor.to_list(length=100)
    for v in vendeurs:
        v["_id"] = str(v["_id"])
    return {"vendeurs": vendeurs}
