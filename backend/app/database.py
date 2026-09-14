import os
import motor.motor_asyncio
from datetime import datetime
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))

MONGO_URI = os.getenv("MONGO_URI", "")
DB_NAME = os.getenv("DB_NAME", "aisy_market")

client = None
db = None

if MONGO_URI:
    try:
        client = motor.motor_asyncio.AsyncIOMotorClient(
            MONGO_URI,
            serverSelectionTimeoutMS=10000,
            tls=True,
        )
        db = client[DB_NAME]
    except Exception as e:
        print(f"[WARNING] MongoDB connection failed: {e}")


async def init_db():
    if db is None:
        print("[WARNING] MongoDB non disponible. Backend demarre sans base de donnees.")
        return None

    try:
        collections = await db.list_collection_names()
    except Exception as e:
        print(f"[WARNING] MongoDB ping failed: {e}. Backend demarre sans base de donnees.")
        return None

    # ── Products ──
    if "products" not in collections:
        await db.create_collection("products")
    await db.products.create_index([("titre", "text"), ("name", "text"), ("description", "text")], background=True)
    await db.products.create_index("category", background=True)
    await db.products.create_index("price", background=True)
    await db.products.create_index("vendeur_id", background=True)
    await db.products.create_index("seller_id", background=True)
    await db.products.create_index("statut", background=True)
    await db.products.create_index("created_at", background=True)
    await db.products.create_index("date_publication", background=True)

    # ── Users ──
    if "users" not in collections:
        await db.create_collection("users")
    await db.users.create_index("email", unique=True, background=True)

    # ── Orders ──
    if "orders" not in collections:
        await db.create_collection("orders")
    await db.orders.create_index("user_id", background=True)
    await db.orders.create_index([("user_id", 1), ("created_at", -1)], background=True)
    await db.orders.create_index("seller_id", background=True)
    await db.orders.create_index("status", background=True)

    # ── Vendeurs ──
    if "vendeurs" not in collections:
        await db.create_collection("vendeurs")
    await db.vendeurs.create_index("email", unique=True, background=True)

    # ── Chats ──
    if "chats" not in collections:
        await db.create_collection("chats")
    await db.chats.create_index("buyer_id", background=True)
    await db.chats.create_index("seller_id", background=True)
    await db.chats.create_index([("buyer_id", 1), ("updatedAt", -1)], background=True)
    await db.chats.create_index([("seller_id", 1), ("updatedAt", -1)], background=True)
    await db.chats.create_index("participants", background=True)

    # ── Messages ──
    if "messages" not in collections:
        await db.create_collection("messages")
    await db.messages.create_index("chatId", background=True)
    await db.messages.create_index([("chatId", 1), ("timestamp", 1)], background=True)
    await db.messages.create_index("senderId", background=True)

    # ── Publicites ──
    if "publicites" not in collections:
        await db.create_collection("publicites")
    await db.publicites.create_index([("active", -1), ("createdAt", -1)], background=True)

    # ── Demands ──
    if "demands" not in collections:
        await db.create_collection("demands")
    await db.demands.create_index("query", background=True)

    # ── Stats ──
    if "stats" not in collections:
        await db.create_collection("stats")

    # ── Notifications ──
    if "notifications" not in collections:
        await db.create_collection("notifications")
    await db.notifications.create_index("userId", background=True)

    # ── Notification Counts ──
    if "notification_counts" not in collections:
        await db.create_collection("notification_counts")

    return db
