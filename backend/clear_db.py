import asyncio
import os
from urllib.parse import quote_plus
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

MONGO_URI = os.getenv("MONGO_URI", "")
if "EzY_M@rket_2026!" in MONGO_URI:
    MONGO_URI = MONGO_URI.replace("EzY_M@rket_2026!", quote_plus("EzY_M@rket_2026!"))

DB_NAME = os.getenv("DB_NAME", "aisy_market")

def clear_all():
    client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=10000)
    try:
        client.admin.command('ping')
        print("Connecté à MongoDB Atlas !")
    except Exception as e:
        print(f"Erreur de connexion: {e}")
        return

    db = client[DB_NAME]
    collections = db.list_collection_names()
    print(f"Collections trouvées: {collections}")

    for col in collections:
        count = db[col].count_documents({})
        if count > 0:
            db[col].drop()
            print(f"  ✓ {col}: {count} documents supprimés")
        else:
            print(f"  - {col}: déjà vide")

    print("\nBase de données vidée avec succès !")
    client.close()

if __name__ == "__main__":
    clear_all()