import os
import motor.motor_asyncio

MONGO_URI = os.getenv("MONGO_URI")
if not MONGO_URI:
    raise RuntimeError("MONGO_URI manquant. Configurez-le dans les variables d'environnement Render.")

DB_NAME = os.getenv("DB_NAME", "aisy_market")

client = motor.motor_asyncio.AsyncIOMotorClient(MONGO_URI)
db = client[DB_NAME]

async def init_db():
    collections = await db.list_collection_names()
    if "products" not in collections:
        await db.create_collection("products")
        await db.products.create_index([("name", "text"), ("description", "text")])
        await db.products.create_index("category")
        await db.products.create_index("price")
        await db.products.create_index("vendeur_id")
    if "users" not in collections:
        await db.create_collection("users")
        await db.users.create_index("email", unique=True)
    if "orders" not in collections:
        await db.create_collection("orders")
        await db.orders.create_index("user_id")
    if "vendeurs" not in collections:
        await db.create_collection("vendeurs")
        await db.vendeurs.create_index("email", unique=True)
    return db
