import os, hashlib
from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import jwt, JWTError
from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import bcrypt
import pyotp

# ─── Configuration ───
SECRET_KEY = os.getenv("JWT_SECRET")
if not SECRET_KEY:
    raise RuntimeError("JWT_SECRET manquant. Configurez-le dans les variables d'environnement Render.")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 7
REFRESH_TOKEN_EXPIRE_DAYS = 30
JWT_ISSUER = "aisy-market"

security = HTTPBearer(auto_error=False)

# ─── Password hashing (bcrypt) ───
def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())

# ─── JWT Tokens ───
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + (expires_delta or timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS))
    to_encode.update({
        "exp": expire,
        "iat": now,
        "iss": JWT_ISSUER,
        "type": "access",
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({
        "exp": expire,
        "iat": now,
        "iss": JWT_ISSUER,
        "type": "refresh",
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], issuer=JWT_ISSUER)
        return payload
    except JWTError:
        raise HTTPException(401, "Token invalide ou expiré")

# ─── HttpOnly cookie helpers ───
def set_auth_cookies(response, access_token: str, refresh_token: str = None):
    secure = os.getenv("ENV", "development") == "production"
    same_site = "lax" if not secure else "strict"
    response.set_cookie(
        key="access_token",
        value=access_token,
        httponly=True,
        secure=secure,
        samesite=same_site,
        max_age=ACCESS_TOKEN_EXPIRE_DAYS * 86400,
        path="/",
    )
    if refresh_token:
        response.set_cookie(
            key="refresh_token",
            value=refresh_token,
            httponly=True,
            secure=secure,
            samesite=same_site,
            max_age=REFRESH_TOKEN_EXPIRE_DAYS * 86400,
            path="/api/auth/refresh",
        )

def clear_auth_cookies(response):
    response.delete_cookie("access_token", path="/")
    response.delete_cookie("refresh_token", path="/api/auth/refresh")

# ─── Dependency: get current user from token ───
async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> dict:
    token = None
    # Try HttpOnly cookie first
    token = request.cookies.get("access_token")
    # Fallback to Authorization header (for mobile/non-browser clients)
    if not token and credentials:
        token = credentials.credentials

    if not token:
        raise HTTPException(401, "Authentification requise")

    payload = decode_token(token)
    return payload

def require_role(*roles: str):
    async def role_checker(current_user: dict = Depends(get_current_user)):
        user_role = current_user.get("role", "client")
        if roles and user_role not in roles:
            raise HTTPException(403, "Accès interdit - privilèges insuffisants")
        return current_user
    return role_checker

# ─── MFA / TOTP ───
def generate_mfa_secret() -> str:
    return pyotp.random_base32()

def get_mfa_uri(secret: str, email: str) -> str:
    return pyotp.totp.TOTP(secret).provisioning_uri(name=email, issuer_name="Easy Market")

def verify_mfa_code(secret: str, code: str) -> bool:
    totp = pyotp.TOTP(secret)
    return totp.verify(code, valid_window=1)

# ─── OAuth state token ───
def create_oauth_state() -> str:
    return hashlib.sha256(os.urandom(64)).hexdigest()

# ─── RBAC helpers ───
ROLE_HIERARCHY = {"admin": 100, "vendeur": 50, "client": 10}

def has_permission(user_role: str, required_role: str) -> bool:
    return ROLE_HIERARCHY.get(user_role, 0) >= ROLE_HIERARCHY.get(required_role, 0)
