from fastapi import APIRouter, HTTPException, Request, Depends, Response
from app.database import db
from app.models import User
from app.auth import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, decode_token,
    set_auth_cookies, clear_auth_cookies,
    get_current_user, require_role,
    generate_mfa_secret, get_mfa_uri, verify_mfa_code,
    create_oauth_state,
)
from datetime import datetime, timedelta
from bson import ObjectId
import re, httpx, os

router = APIRouter()

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "http://localhost:8000/api/auth/google/callback")

# ─── Register ───
@router.post("/api/users/register")
async def register(user: User, response: Response):
    existing = await db.users.find_one({"email": user.email})
    if existing:
        raise HTTPException(400, "Email déjà utilisé")
    doc = user.model_dump()
    doc["password"] = hash_password(user.password)
    doc["role"] = "client"
    doc["mfa_secret"] = None
    doc["mfa_enabled"] = False
    doc["created_at"] = datetime.utcnow()
    result = await db.users.insert_one(doc)

    payload = {
        "sub": str(result.inserted_id),
        "email": user.email,
        "name": user.name,
        "role": "client",
        "mfa_required": False,
    }
    access_token = create_access_token(payload)
    refresh_token = create_refresh_token({"sub": str(result.inserted_id)})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {"_id": str(result.inserted_id), "email": user.email, "name": user.name, "role": "client"},
        "mfa_required": False,
    }

# ─── Login ───
@router.post("/api/users/login")
async def login(data: dict, response: Response):
    email = data.get("email", "")
    password = data.get("password", "")
    user = await db.users.find_one({"email": email})
    if not user or not verify_password(password, user["password"]):
        # Legacy SHA256 fallback for existing users
        import hashlib
        if user and user.get("password", "").startswith("$2b$") == False:
            if user["password"] != hashlib.sha256(password.encode()).hexdigest():
                raise HTTPException(401, "Email ou mot de passe incorrect")
        else:
            raise HTTPException(401, "Email ou mot de passe incorrect")

    # If user has MFA enabled, return mfa_required flag
    if user.get("mfa_enabled"):
        # Generate a temporary token for MFA verification
        temp_token = create_access_token({
            "sub": str(user["_id"]),
            "email": user["email"],
            "name": user.get("name", ""),
            "role": user.get("role", "client"),
            "mfa_pending": True,
        }, expires_delta=timedelta(minutes=5))
        return {
            "mfa_required": True,
            "mfa_token": temp_token,
            "user": {"email": user["email"]},
        }

    payload = {
        "sub": str(user["_id"]),
        "email": user["email"],
        "name": user.get("name", ""),
        "role": user.get("role", "client"),
        "mfa_required": False,
    }
    access_token = create_access_token(payload)
    refresh_token = create_refresh_token({"sub": str(user["_id"])})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {"_id": str(user["_id"]), "email": user["email"], "name": user.get("name", ""), "role": user.get("role", "client")},
        "mfa_required": False,
    }

# ─── MFA Verify (second step after login) ───
@router.post("/api/users/mfa/verify")
async def mfa_verify(data: dict, response: Response):
    mfa_token = data.get("mfa_token", "")
    code = data.get("code", "")

    payload = decode_token(mfa_token)
    if not payload.get("mfa_pending"):
        raise HTTPException(400, "Token invalide pour la vérification MFA")

    user_id = payload["sub"]
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if not user or not user.get("mfa_secret"):
        raise HTTPException(400, "MFA non configuré")

    if not verify_mfa_code(user["mfa_secret"], code):
        raise HTTPException(401, "Code MFA invalide")

    final_payload = {
        "sub": user_id,
        "email": user["email"],
        "name": user.get("name", ""),
        "role": user.get("role", "client"),
        "mfa_required": False,
    }
    access_token = create_access_token(final_payload)
    refresh_token = create_refresh_token({"sub": user_id})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {"_id": user_id, "email": user["email"], "name": user.get("name", ""), "role": user.get("role", "client")},
        "mfa_required": False,
    }

# ─── MFA Setup ───
@router.post("/api/users/mfa/setup")
async def mfa_setup(current_user: dict = Depends(get_current_user)):
    user_id = current_user["sub"]
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if not user:
        raise HTTPException(404, "Utilisateur non trouvé")

    secret = generate_mfa_secret()
    uri = get_mfa_uri(secret, user["email"])

    # Store temporarily until verified
    await db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"mfa_pending_secret": secret}}
    )

    return {"secret": secret, "uri": uri}

# ─── MFA Confirm ───
@router.post("/api/users/mfa/confirm")
async def mfa_confirm(data: dict, current_user: dict = Depends(get_current_user)):
    user_id = current_user["sub"]
    code = data.get("code", "")

    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if not user or not user.get("mfa_pending_secret"):
        raise HTTPException(400, "Configurez d'abord le MFA")

    if not verify_mfa_code(user["mfa_pending_secret"], code):
        raise HTTPException(401, "Code invalide")

    await db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"mfa_secret": user["mfa_pending_secret"], "mfa_enabled": True},
         "$unset": {"mfa_pending_secret": ""}}
    )

    return {"mfa_enabled": True, "message": "MFA activé avec succès"}

# ─── MFA Disable ───
@router.post("/api/users/mfa/disable")
async def mfa_disable(data: dict, current_user: dict = Depends(get_current_user)):
    user_id = current_user["sub"]
    code = data.get("code", "")

    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if not user or not user.get("mfa_secret"):
        raise HTTPException(400, "MFA non configuré")

    if not verify_mfa_code(user["mfa_secret"], code):
        raise HTTPException(401, "Code invalide")

    await db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"mfa_enabled": False}, "$unset": {"mfa_secret": "", "mfa_pending_secret": ""}}
    )

    return {"mfa_enabled": False, "message": "MFA désactivé"}

# ─── OAuth Google ───
@router.get("/api/auth/google/login")
async def google_login():
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(500, "OAuth non configuré - GOOGLE_CLIENT_ID manquant")
    state = create_oauth_state()
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "offline",
    }
    from urllib.parse import urlencode
    url = f"https://accounts.google.com/o/oauth2/v2/auth?{urlencode(params)}"
    return {"url": url, "state": state}

@router.get("/api/auth/google/callback")
async def google_callback(code: str = "", state: str = "", response: Response = None):
    if not code:
        raise HTTPException(400, "Code d'autorisation manquant")

    # Exchange code for tokens
    async with httpx.AsyncClient() as client:
        token_res = await client.post("https://oauth2.googleapis.com/token", data={
            "code": code,
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "redirect_uri": GOOGLE_REDIRECT_URI,
            "grant_type": "authorization_code",
        })
        if token_res.status_code != 200:
            raise HTTPException(400, "Échange de code OAuth échoué")
        tokens = token_res.json()
        id_token = tokens.get("id_token")

        # Verify id_token
        from jose import jwt as jose_jwt
        google_keys = await client.get("https://www.googleapis.com/oauth2/v3/certs")
        keys = google_keys.json()
        header = jose_jwt.get_unverified_header(id_token)
        key = next((k for k in keys["keys"] if k["kid"] == header["kid"]), None)
        if not key:
            raise HTTPException(400, "Clé de vérification OAuth non trouvée")

        user_info = jose_jwt.decode(id_token, key, algorithms=["RS256"],
                                     audience=GOOGLE_CLIENT_ID,
                                     issuer="https://accounts.google.com")

    google_email = user_info.get("email")
    google_name = user_info.get("name", google_email)

    # Find or create user
    user = await db.users.find_one({"email": google_email})
    user_role = "client"
    if not user:
        doc = {
            "email": google_email,
            "name": google_name,
            "password": hash_password(os.urandom(32).hex()),
            "role": "client",
            "oauth_provider": "google",
            "mfa_secret": None,
            "mfa_enabled": False,
            "created_at": datetime.utcnow(),
        }
        result = await db.users.insert_one(doc)
        user_id = str(result.inserted_id)
    else:
        user_id = str(user["_id"])
        user_role = user.get("role", "client")

    payload = {
        "sub": user_id,
        "email": google_email,
        "name": google_name,
        "role": user_role,
        "mfa_required": False,
    }
    access_token = create_access_token(payload)
    refresh_token = create_refresh_token({"sub": user_id})
    set_auth_cookies(response, access_token, refresh_token)

    return {
        "user": {"_id": user_id, "email": google_email, "name": google_name, "role": user_role},
        "mfa_required": False,
    }

# ─── Token Refresh ───
@router.post("/api/auth/refresh")
async def refresh_token(request: Request, response: Response):
    refresh_token_str = request.cookies.get("refresh_token")
    if not refresh_token_str:
        raise HTTPException(401, "Token de rafraîchissement manquant")

    payload = decode_token(refresh_token_str)
    if payload.get("type") != "refresh":
        raise HTTPException(401, "Type de token invalide")

    # Verify user still exists
    user = await db.users.find_one({"_id": ObjectId(payload["sub"])})
    if not user:
        clear_auth_cookies(response)
        raise HTTPException(401, "Utilisateur non trouvé")

    new_payload = {
        "sub": payload["sub"],
        "email": user["email"],
        "name": user.get("name", ""),
        "role": user.get("role", "client"),
        "mfa_required": False,
    }
    new_access = create_access_token(new_payload)
    set_auth_cookies(response, new_access)
    return {"message": "Token rafraîchi"}

# ─── Logout ───
@router.post("/api/users/logout")
async def logout(response: Response):
    clear_auth_cookies(response)
    return {"message": "Déconnecté"}

# ─── Me (current user profile) ───
@router.get("/api/users/me")
async def get_me(current_user: dict = Depends(get_current_user)):
    user = await db.users.find_one({"_id": ObjectId(current_user["sub"])})
    if not user:
        raise HTTPException(404, "Utilisateur non trouvé")
    user["_id"] = str(user["_id"])
    user.pop("password", None)
    user.pop("mfa_secret", None)
    user.pop("mfa_pending_secret", None)
    return user
