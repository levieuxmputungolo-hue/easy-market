"""Endpoint de diagnostic /api/health — aucune donnee secrete n'est renvoyee.

Seuls sont exposes : presence de l'URI, utilisateur, hote, longueur et
anomalies de forme. Jamais le mot de passe.
"""
import os
import time
import asyncio

from fastapi import APIRouter
from app.database import MONGO_URI, DB_NAME, db, connect_attempts, sanitize_error, _uri_variants

router = APIRouter()
_START = time.time()


def _uri_report(uri: str) -> dict:
    """Analyse structurelle d'une URI MongoDB, sans exposer le secret."""
    if not uri:
        return {"configured": False}
    if "://" not in uri:
        return {"configured": True, "scheme": "?", "anomalie": "pas de schema ://", "length": len(uri)}

    scheme, rest = uri.split("://", 1)
    authority = rest.split("/", 1)[0]
    has_at = "@" in authority
    host = authority.rsplit("@", 1)[-1] if has_at else authority
    host = host.split("?", 1)[0]

    anomalies = []
    if not has_at:
        anomalies.append("pas de separateur @ : userinfo absent")
    if not host:
        anomalies.append("HOST VIDE (provoque l'erreur 'A DNS label is empty')")
    if ".." in host or host.startswith(".") or host.endswith("."):
        anomalies.append("HOST avec point vide (label vide DNS)")
    if any(c.isspace() for c in host):
        anomalies.append("HOST contient des espaces/caracteres de fin de ligne")
    if host.count("@") > 0:
        anomalies.append("HOST contient encore un @ (mot de passe non encode ?)")
    if len(host) < 8:
        anomalies.append(f"HOST suspect ({host!r})")

    userinfo = authority.rsplit("@", 1)[0] if has_at else ""
    user = userinfo.split(":", 1)[0]

    # `tail` = fin de l'URI APRES le dernier @ : jamais d'identifiant dedans.
    after_authority = uri.rsplit("@", 1)[-1] if has_at else ""
    tail = after_authority[-40:]

    return {
        "configured": True,
        "scheme": scheme,
        "username": user,
        "host": host,
        "length": len(uri),
        "has_password": ":" in userinfo,
        "password_encoded": "%40" in userinfo,
        "password_raw_at": "@" in userinfo.split(":", 1)[-1],
        "tail": tail,
        "variants_testables": [name for name, _ in _uri_variants(uri)],
        "anomalies": anomalies,
    }


@router.get("/api/health")
async def health():
    """Etat reel du backend : config, connexion MongoDB, latence."""
    report = {
        "status": "ok",
        "uptime_s": round(time.time() - _START, 1),
        "env": os.getenv("ENV", "?"),
        "mongo": _uri_report(MONGO_URI),
        "db_name": DB_NAME,
        "db_available": bool(db.available),
        "connect_attempts": connect_attempts,
        "database": None,
    }

    if not db.available:
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
            "error": sanitize_error(e),
        }
    return report
