import os
import re
import asyncio
import motor.motor_asyncio
from dotenv import load_dotenv
from urllib.parse import quote_plus, unquote_plus, urlparse, urlunparse

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))

MONGO_URI = os.getenv("MONGO_URI", "")
DB_NAME = os.getenv("DB_NAME", "aisy_market")

client = None
connect_attempts = []   # diagnostique expose par /api/health (aucun secret)


class DatabaseUnavailable(RuntimeError):
    """Leve quand on interroge la base alors qu'aucune connexion n'a reussi."""


class _DbProxy:
    """Proxy stable : tous les routers importent `db` une seule fois.

    Le vrai client Mongo est branche ici au runtime (init_db), donc les
    imports par valeur dans les routers restent valides.
    """

    _real = None

    def _bind(self, real_db):
        self._real = real_db

    @property
    def available(self):
        return self._real is not None

    def __getattr__(self, name):
        if self._real is None:
            raise DatabaseUnavailable(
                "MongoDB non connecte : verifiez MONGO_URI (voir /api/health)"
            )
        return getattr(self._real, name)


db = _DbProxy()


def sanitize_error(text) -> str:
    """Retire tout identifiant/mot de passe URI d'un message d'erreur."""
    text = str(text)
    text = re.sub(r"mongodb(\+srv)?://[^@\s]+@", "mongodb://***:***@", text)
    text = re.sub(r"//[^@\s/:]+:[^@\s/]+@", "//***:***@", text)
    return text[:500]


def _encode_mongo_uri(uri: str) -> str:
    """Encode username:password in MongoDB URI per RFC 3986."""
    if "@" not in uri:
        return uri
    parsed = urlparse(uri)
    if parsed.username:
        user = quote_plus(parsed.username)
        password = quote_plus(parsed.password) if parsed.password else ""
        netloc = f"{user}:{password}@{parsed.hostname}"
        if parsed.port:
            netloc += f":{parsed.port}"
        return urlunparse(parsed._replace(netloc=netloc))
    return uri


def _uri_variants(uri: str):
    """Retourne [(variante, uri)] a essayer dans l'ordre.

    Certains environnements (Render) stockent l'URI avec des identifiants
    deja encodes : un encodage aveugle produit alors un mauvais mot de passe
    et MongoDB renvoie « authentication failed ». On essaie donc plusieurs
    interpretations jusqu'a ce que le ping reussisse.
    """
    if "@" not in uri or "://" not in uri:
        return [("unique", uri)]

    variants = [("encode", _encode_mongo_uri(uri))]

    # Deuxieme interpretation : on decode d'abord ce qui est encode,
    # puis on re-encode proprement (corrige un double encodage).
    try:
        parsed = urlparse(uri)
        if parsed.username:
            user = unquote_plus(parsed.username)
            password = unquote_plus(parsed.password) if parsed.password else ""
            netloc = quote_plus(user)
            if password:
                netloc += ":" + quote_plus(password)
            netloc += "@" + (parsed.hostname or "")
            if parsed.port:
                netloc += f":{parsed.port}"
            decoded = urlunparse(parsed._replace(netloc=netloc))
            if decoded != variants[0][1]:
                variants.append(("re-encode", decoded))
    except Exception:
        pass

    # Troisieme interpretation : URI telle quelle (si pymongo l'accepte).
    if uri != variants[0][1]:
        variants.append(("brut", uri))

    return variants


async def init_db():
    """Branche le premier client dont le ping reussit, puis cree les index.

    Budget par variante : 20 s (connexion en tache de fond, sans impact sur
    le demarrage ; Render est de toute facon plus rapide que ce budget).
    """
    if not MONGO_URI:
        print("[ERREUR] MONGO_URI absente : la base ne sera pas disponible.")
        return None

    connect_attempts.clear()
    bound = None

    for label, candidate in _uri_variants(MONGO_URI):
        try:
            c = motor.motor_asyncio.AsyncIOMotorClient(
                candidate,
                serverSelectionTimeoutMS=20000,
                tls=True,
            )
            await asyncio.wait_for(c.admin.command("ping"), timeout=22)
        except Exception as e:
            msg = sanitize_error(e) or type(e).__name__
            connect_attempts.append({"variant": label, "ok": False, "error": msg})
            print(f"[DB] variante '{label}' KO : {msg}")
            continue

        connect_attempts.append({"variant": label, "ok": True, "error": ""})
        print(f"[DB] connexion reussie via la variante '{label}'")
        client = c
        db._bind(client[DB_NAME])
        bound = client[DB_NAME]
        break

    if bound is None:
        print("[ERREUR] Aucune variante de MONGO_URI n'a fonctionne : base injoignable.")
        return None

    collections = await bound.list_collection_names()

    # ── Products ──
    if "products" not in collections:
        await bound.create_collection("products")
    try:
        await bound.products.drop_index("name_text_description_text")
    except Exception:
        pass
    await bound.products.create_index([("titre", "text"), ("name", "text"), ("description", "text")], background=True, name="titre_text_name_text_description_text")
    await bound.products.create_index("category", background=True)
    await bound.products.create_index("price", background=True)
    await bound.products.create_index("vendeur_id", background=True)
    await bound.products.create_index("seller_id", background=True)
    await bound.products.create_index("statut", background=True)
    await bound.products.create_index("created_at", background=True)
    await bound.products.create_index("date_publication", background=True)

    # ── Users ──
    if "users" not in collections:
        await bound.create_collection("users")
    await bound.users.create_index("email", unique=True, background=True)

    # ── Orders ──
    if "orders" not in collections:
        await bound.create_collection("orders")
    await bound.orders.create_index("user_id", background=True)
    await bound.orders.create_index([("user_id", 1), ("created_at", -1)], background=True)
    await bound.orders.create_index("seller_id", background=True)
    await bound.orders.create_index("status", background=True)

    # ── Vendeurs ──
    if "vendeurs" not in collections:
        await bound.create_collection("vendeurs")
    await bound.vendeurs.create_index("email", unique=True, background=True)

    # ── Chats ──
    if "chats" not in collections:
        await bound.create_collection("chats")
    await bound.chats.create_index("buyer_id", background=True)
    await bound.chats.create_index("seller_id", background=True)
    await bound.chats.create_index([("buyer_id", 1), ("updatedAt", -1)], background=True)
    await bound.chats.create_index([("seller_id", 1), ("updatedAt", -1)], background=True)
    await bound.chats.create_index("participants", background=True)

    # ── Messages ──
    if "messages" not in collections:
        await bound.create_collection("messages")
    await bound.messages.create_index("chatId", background=True)
    await bound.messages.create_index([("chatId", 1), ("timestamp", 1)], background=True)
    await bound.messages.create_index("senderId", background=True)

    # ── Publicites ──
    if "publicites" not in collections:
        await bound.create_collection("publicites")
    await bound.publicites.create_index([("active", -1), ("createdAt", -1)], background=True)

    # ── Demands ──
    if "demands" not in collections:
        await bound.create_collection("demands")
    await bound.demands.create_index("query", background=True)

    # ── Stats ──
    if "stats" not in collections:
        await bound.create_collection("stats")

    # ── Notifications ──
    if "notifications" not in collections:
        await bound.create_collection("notifications")
    await bound.notifications.create_index("userId", background=True)

    # ── Notification Counts ──
    if "notification_counts" not in collections:
        await bound.create_collection("notification_counts")

    return db


async def ensure_db():
    """Garde-fou : leve DatabaseUnavailable si la base n'est pas branchee."""
    if not db.available:
        raise DatabaseUnavailable("MongoDB non connecte (voir /api/health)")
    return db
