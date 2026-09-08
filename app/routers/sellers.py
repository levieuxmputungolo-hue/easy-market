from fastapi import APIRouter, Query
from app.database import db
import math

router = APIRouter()

# Kinshasa communes coordinates (approximate centers)
COMMUNES = {
    "Gombe":      {"lat": -4.3090, "lng": 15.3150},
    "Kinshasa":   {"lat": -4.3317, "lng": 15.3139},
    "Limete":     {"lat": -4.3630, "lng": 15.3450},
    "Ngaliema":   {"lat": -4.3410, "lng": 15.2610},
    "Kalamu":     {"lat": -4.3310, "lng": 15.3200},
    "Bandal":     {"lat": -4.3210, "lng": 15.2900},
    "Matete":     {"lat": -4.3780, "lng": 15.3480},
    "Ndjili":     {"lat": -4.4010, "lng": 15.3730},
    "Kisenso":    {"lat": -4.4110, "lng": 15.3400},
    "Masina":     {"lat": -4.3800, "lng": 15.3900},
    "Kimbanseke": {"lat": -4.4250, "lng": 15.3650},
    "Lemba":      {"lat": -4.3650, "lng": 15.3220},
    "Mont Ngafula": {"lat": -4.4210, "lng": 15.2860},
    "Nsele":      {"lat": -4.2960, "lng": 15.4830},
}

def haversine(lat1, lng1, lat2, lng2):
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return round(R * c, 1)

@router.get("/api/sellers")
async def get_sellers():
    cursor = db.sellers.find({})
    sellers = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        sellers.append(doc)
    return sellers

@router.get("/api/sellers/nearby")
async def nearby_sellers(
    lat: float = Query(...),
    lng: float = Query(...),
    max_km: float = Query(50.0, le=200),
):
    cursor = db.sellers.find({})
    results = []
    async for doc in cursor:
        s_lat = doc.get("latitude", 0)
        s_lng = doc.get("longitude", 0)
        dist = haversine(lat, lng, s_lat, s_lng)
        if dist <= max_km:
            doc["_id"] = str(doc["_id"])
            doc["distance_km"] = dist
            results.append(doc)
    results.sort(key=lambda x: x["distance_km"])
    return results

@router.get("/api/sellers/commune/{commune}")
async def sellers_by_commune(commune: str):
    cursor = db.sellers.find({"commune": {"$regex": commune, "$options": "i"}})
    sellers = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        sellers.append(doc)
    return sellers

@router.get("/api/communes")
async def get_communes():
    return [
        {"name": k, "lat": v["lat"], "lng": v["lng"]}
        for k, v in COMMUNES.items()
    ]
