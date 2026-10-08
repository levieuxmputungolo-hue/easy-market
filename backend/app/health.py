"""Endpoint de diagnostic /api/health — aucune donnée secrete n'est renvoyée."""
import os
import re
import time
import asyncio

from fastapi import APIRouter
from app.database import MONGO_URI, DB_NAME, db, client

router = APIRouter()
_START = time.time()


def _sanitize(text: str) -> str:
    """Supprime tout identifiant/mot de passe de type URI d'un message d'erreur."""
    text = str(text)
    text = re.sub(r"mongodb(\+srv)?://[^@\s]+@", "mongodb://***:***@", text)
    text = re.sub(r"//[^@\s/:]+:[^@\s/]+@", "//***:***@", text)
    return text[:500]


@router.get("/api/health")
async def health():
    """Etat reel du backend : config, connexion MongoDB, latence."""
    report = {
        "status": "ok",
        "uptime_s": round(time.time() - _START, 1),
        "env": os.getenv("ENV", "?"),
        "mongo_uri_configured": bool(MONGO_URI),
        "mongo_uri_scheme": (MONGO_URI.split("://", 1)[0] if "://" in MONGO_URI else "?"),
        "db_name": DB_NAME,
        "db_available": db is not None,
        "database": None,
    }

    if db is None:
        report["status"] = "degraded"
        report["error"] = "MONGO_URI absente ou invalide : le backend tourne sans base de donnees"
        return report

    t0 = time.time()
    try:
        await asyncio.wait_for(db.command("ping"), timeout=8)
        report["database"] = {
            "ping": "ok",
            "latency_ms": round((time.time() - t0) * 1000, 1),
            "collections": await db.list_collection_names(),
        }
    except Exception as e:
        report["status"] = "degraded"
        report["database"] = {
            "ping": "ko",
            "latency_ms": round((time.time() - t0) * 1000, 1),
            "error": _sanitize(e),
        }
    return report
