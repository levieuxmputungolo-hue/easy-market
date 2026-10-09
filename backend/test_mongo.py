import asyncio, os, sys, traceback
from dotenv import load_dotenv
from urllib.parse import quote_plus, urlparse, urlunparse

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
uri = os.getenv("MONGO_URI", "")
print("DB_NAME =", os.getenv("DB_NAME", "aisy_market"))
if not uri:
    print("MONGO_URI vide !"); sys.exit(1)

def encode(u):
    if "@" not in u: return u
    p = urlparse(u)
    if p.username:
        user = quote_plus(p.username)
        pw = quote_plus(p.password) if p.password else ""
        netloc = f"{user}:{pw}@{p.hostname}"
        if p.port: netloc += f":{p.port}"
        return urlunparse(p._replace(netloc=netloc))
    return u

enc = encode(uri)
print("host =", urlparse(enc).hostname)

import motor.motor_asyncio

async def main():
    try:
        client = motor.motor_asyncio.AsyncIOMotorClient(enc, serverSelectionTimeoutMS=15000, tls=True)
        await client.admin.command("ping")
        print("PING OK")
        db = client[os.getenv("DB_NAME", "aisy_market")]
        names = await db.list_collection_names()
        print("collections:", names)
        n = await db.products.count_documents({})
        print("products count:", n)
        nv = await db.vendeurs.count_documents({})
        print("vendeurs count:", nv)
    except Exception as e:
        print("ERREUR:", type(e).__name__, e)
        traceback.print_exc()

asyncio.run(main())
