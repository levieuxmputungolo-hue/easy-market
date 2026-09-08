import asyncio
from app.database import db, init_db
from app.auth import hash_password
from datetime import datetime

async def seed():
    await init_db()
    count = await db.products.count_documents({})
    if count > 0:
        print(f"Deja {count} produits, skip seed")
        return

    products = [
        {"name": "iPhone 15 Pro Max 256Go", "description": "Smartphone Apple dernier cri, écran 6.7\", triple appareil photo 48MP", "price": 1499.99, "category": "Smartphones", "image": "https://images.unsplash.com/photo-1592750475338-74b7b21085ab?w=400&h=400&fit=crop", "seller_id": "1", "seller_name": "TechStore Pro", "rating": 4.8, "stock": 15, "salesCount": 1500},
        {"name": "Samsung Galaxy S24 Ultra", "description": "Smartphone Samsung avec IA intégrée, écran 6.8\", S-Pen", "price": 1349.99, "category": "Smartphones", "image": "https://images.unsplash.com/photo-1610945265064-0e34e5519b5f?w=400&h=400&fit=crop", "seller_id": "1", "seller_name": "TechStore Pro", "rating": 4.7, "stock": 20, "salesCount": 1200},
        {"name": "MacBook Air M3 15\"", "description": "Ordinateur portable Apple puce M3, 18h autonomie", "price": 1599.99, "category": "Ordinateurs", "image": "https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=400&h=400&fit=crop", "seller_id": "1", "seller_name": "TechStore Pro", "rating": 4.9, "stock": 10, "salesCount": 800},
        {"name": "Casque Audio Sony WH-1000XM5", "description": "Casque Bluetooth anti-bruit avec réduction active", "price": 349.99, "category": "Audio", "image": "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400&h=400&fit=crop", "seller_id": "2", "seller_name": "FashionHub", "rating": 4.6, "stock": 30, "salesCount": 2500},
        {"name": "Montre Connectée Apple Watch Ultra 2", "description": "Montre connectée sport, GPS, oxymètre, 36h batterie", "price": 899.99, "category": "Accessoires", "image": "https://images.unsplash.com/photo-1546868871-af0de0ae72b6?w=400&h=400&fit=crop", "seller_id": "1", "seller_name": "TechStore Pro", "rating": 4.7, "stock": 12, "salesCount": 950},
        {"name": "Tablette iPad Pro M4 12.9\"", "description": "Tablette Apple puce M4, écran OLED, compatibilité Apple Pencil", "price": 1299.99, "category": "Ordinateurs", "image": "https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?w=400&h=400&fit=crop", "seller_id": "1", "seller_name": "TechStore Pro", "rating": 4.8, "stock": 8, "salesCount": 600},
        {"name": "Robot Aspirateur Roomba j9+", "description": "Aspirateur robot intelligent avec vidage automatique", "price": 799.99, "category": "Maison", "image": "https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400&h=400&fit=crop", "seller_id": "3", "seller_name": "Maison & Deco", "rating": 4.5, "stock": 25, "salesCount": 400},
        {"name": "Enceinte Bluetooth JBL Charge 5", "description": "Enceinte portable étanche 20h d'autonomie, son puissant", "price": 179.99, "category": "Audio", "image": "https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?w=400&h=400&fit=crop", "seller_id": "2", "seller_name": "FashionHub", "rating": 4.4, "stock": 40, "salesCount": 3200},
        {"name": "Chaussures Nike Air Max 270", "description": "Chaussures de sport confortables avec semelle Air Max", "price": 189.99, "category": "Mode", "image": "https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400&h=400&fit=crop", "seller_id": "2", "seller_name": "FashionHub", "rating": 4.3, "stock": 50, "salesCount": 2800},
        {"name": "Sac à Dos Eastpak Provider", "description": "Sac à dos 40L avec compartiment ordinateur 15.6\"", "price": 79.99, "category": "Mode", "image": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=400&h=400&fit=crop", "seller_id": "2", "seller_name": "FashionHub", "rating": 4.2, "stock": 60, "salesCount": 4500},
    ]
    for p in products:
        p["created_at"] = datetime.utcnow()
    await db.products.insert_many(products)

    user_exists = await db.users.find_one({"email": "demo@aisy.com"})
    if not user_exists:
        await db.users.insert_one({
            "email": "demo@aisy.com",
            "password": hash_password("demo123"),
            "name": "Client Demo",
            "phone": "+243800000000",
            "created_at": datetime.utcnow(),
        })

    # Seed sellers / vendeurs avec communes
    seller_count = await db.sellers.count_documents({})
    if seller_count == 0:
        sellers = [
            {"name": "TechStore Pro", "commune": "Gombe", "latitude": -4.3090, "longitude": 15.3150, "phone": "+243811111111", "email": "techstore@aisy.com", "products_count": 5, "rating": 4.8, "image": "https://images.unsplash.com/photo-1560250097-0b93528c311a?w=200&h=200&fit=crop", "verified": True},
            {"name": "FashionHub", "commune": "Ngaliema", "latitude": -4.3410, "longitude": 15.2610, "phone": "+243822222222", "email": "fashion@aisy.com", "products_count": 3, "rating": 4.3, "image": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop", "verified": True},
            {"name": "Maison & Deco", "commune": "Limete", "latitude": -4.3630, "longitude": 15.3450, "phone": "+243833333333", "email": "deco@aisy.com", "products_count": 1, "rating": 4.5, "image": "https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?w=200&h=200&fit=crop", "verified": False},
            {"name": "ElectroDiscount", "commune": "Kalamu", "latitude": -4.3310, "longitude": 15.3200, "phone": "+243844444444", "email": "electro@aisy.com", "products_count": 8, "rating": 4.1, "image": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop", "verified": False},
            {"name": "Bio Market", "commune": "Bandal", "latitude": -4.3210, "longitude": 15.2900, "phone": "+243855555555", "email": "bio@aisy.com", "products_count": 6, "rating": 4.6, "image": "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop", "verified": True},
        ]
        for s in sellers:
            s["created_at"] = datetime.utcnow()
        await db.sellers.insert_many(sellers)
        print("Vendeurs inseres: 5")
    else:
        print(f"Vendeurs deja presents: {seller_count}")

    print("Seed termine: 10 produits, 5 vendeurs, 1 user demo (demo@aisy.com / demo123)")

if __name__ == "__main__":
    asyncio.run(seed())
