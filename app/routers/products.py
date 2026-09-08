from fastapi import APIRouter, Query, Depends, HTTPException, UploadFile, File, Form
from app.database import db
from app.auth import require_role, get_current_user
from bson import ObjectId
from datetime import datetime
import math, os, re, shutil

router = APIRouter()

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/webm", "video/ogg", "video/quicktime"}
MAX_IMAGE_SIZE = 5 * 1024 * 1024     # 5 MB
MAX_VIDEO_SIZE = 50 * 1024 * 1024    # 50 MB

def _validate_price(price) -> float:
    try:
        p = float(price)
    except (TypeError, ValueError):
        raise HTTPException(400, "Le prix doit être un nombre valide")
    if p <= 0:
        raise HTTPException(400, "Le prix doit être supérieur à 0")
    return p

def _validate_stock(stock) -> int:
    try:
        s = int(stock)
    except (TypeError, ValueError):
        raise HTTPException(400, "Le stock doit être un nombre entier")
    if s < 0:
        raise HTTPException(400, "Le stock ne peut pas être négatif")
    return s

def _validate_image_url(url: str) -> str:
    url = url.strip()
    if url and not url.startswith(("http://", "https://", "data:")):
        raise HTTPException(400, "L'URL de l'image doit commencer par http://, https:// ou data:")
    return url

def _resolve_titre(data: dict) -> str:
    titre = data.get("titre") or data.get("name") or ""
    if not titre.strip():
        raise HTTPException(400, "Le titre est obligatoire")
    return titre.strip()

def _resolve_images(data: dict) -> list:
    raw = data.get("images") or data.get("image") or []
    if isinstance(raw, str):
        return [_validate_image_url(raw)] if raw.strip() else []
    if not isinstance(raw, list):
        return []
    urls = []
    for u in raw:
        if isinstance(u, str) and u.strip():
            urls.append(_validate_image_url(u))
    return urls

def _get_vendeur_id(current_user: dict) -> str:
    return current_user.get("sub") or current_user.get("vendeur_id", "") or ""

async def _fetch_product(product_id: str) -> dict:
    if not ObjectId.is_valid(product_id):
        raise HTTPException(400, "ID produit invalide")
    doc = await db.products.find_one({"_id": ObjectId(product_id)})
    if not doc:
        raise HTTPException(404, "Produit non trouvé")
    return doc

def _check_ownership(doc: dict, vendeur_id: str, current_user: dict):
    if doc.get("vendeur_id") != vendeur_id and current_user.get("role") != "admin":
        raise HTTPException(403, "Ce produit ne vous appartient pas")

@router.get("/api/products")
async def get_products(
    search: str = "",
    category: str = "",
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    sort: str = "created_at",
    order: int = -1,
    min_price: float = 0,
    max_price: float = 0,
):
    query = {"statut": {"$ne": "en_attente"}}
    if search:
        safe_search = re.escape(search)
        query["$or"] = [
            {"titre": {"$regex": safe_search, "$options": "i"}},
            {"name": {"$regex": safe_search, "$options": "i"}},
            {"description": {"$regex": safe_search, "$options": "i"}},
        ]
    if category:
        query["category"] = category
    if min_price > 0 or max_price > 0:
        price_q = {}
        if min_price > 0:
            price_q["$gte"] = min_price
        if max_price > 0:
            price_q["$lte"] = max_price
        if price_q:
            query["price"] = price_q

    total = await db.products.count_documents(query)
    skip = (page - 1) * limit

    sort_field = sort if sort in ("price", "rating", "created_at") else "created_at"
    cursor = db.products.find(query).sort(sort_field, order).skip(skip).limit(limit)
    products = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        products.append(doc)

    return {
        "products": products,
        "total": total,
        "page": page,
        "pages": math.ceil(total / limit),
    }

@router.get("/api/products/{product_id}")
async def get_product(product_id: str):
    if not ObjectId.is_valid(product_id):
        raise HTTPException(400, "ID produit invalide")
    doc = await db.products.find_one({"_id": ObjectId(product_id)})
    if not doc:
        raise HTTPException(404, "Produit non trouvé")
    doc["_id"] = str(doc["_id"])
    return doc

@router.get("/api/categories")
async def get_categories():
    pipeline = [
        {"$group": {"_id": "$category", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
    ]
    cats = []
    async for doc in db.products.aggregate(pipeline):
        cats.append({"name": doc["_id"], "count": doc["count"]})
    return cats

# ─── Vendor Product CRUD (protected) ───

@router.post("/api/vendeurs/produits")
async def create_vendor_product(
    data: dict,
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    titre = _resolve_titre(data)
    price = _validate_price(data.get("price", 0))
    stock = _validate_stock(data.get("stock", 0))
    vendeur_id = _get_vendeur_id(current_user)
    video = (data.get("video") or "").strip()
    if video and not video.startswith(("http://", "https://", "data:")):
        raise HTTPException(400, "L'URL de la vidéo doit commencer par http://, https:// ou data:")

    product = {
        "titre": titre,
        "description": data.get("description", "").strip(),
        "price": price,
        "category": (data.get("category") or "Autre").strip(),
        "images": _resolve_images(data),
        "video": video or None,
        "vendeur_id": vendeur_id,
        "seller_name": data.get("seller_name", current_user.get("full_name", current_user.get("name", "Vendeur"))),
        "rating": 0,
        "reviews": 0,
        "stock": stock,
        "salesCount": 0,
        "statut": "publié",
        "date_publication": datetime.utcnow(),
        "marque": (data.get("marque") or "").strip(),
        "annee": (data.get("annee") or "").strip(),
        "transmission": (data.get("transmission") or "").strip(),
        "carburant": (data.get("carburant") or "").strip(),
        "localisation": (data.get("localisation") or "").strip(),
        "couleur": (data.get("couleur") or "").strip(),
        "documents": (data.get("documents") or "").strip(),
        "prix_negociable": data.get("prix_negociable", False),
        "livraison": data.get("livraison", False),
        "garantie": data.get("garantie", False),
        "seller_id": vendeur_id,
    }
    result = await db.products.insert_one(product)
    product["_id"] = str(result.inserted_id)
    return product


@router.get("/api/vendeurs/produits")
async def list_vendor_products(
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    vendeur_id = _get_vendeur_id(current_user)
    cursor = db.products.find({"vendeur_id": vendeur_id}).sort("date_publication", -1)
    products = []
    async for doc in cursor:
        doc["_id"] = str(doc["_id"])
        products.append(doc)
    return {"products": products, "total": len(products)}


@router.get("/api/vendeurs/produits/stats")
async def vendor_product_stats(
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    vendeur_id = _get_vendeur_id(current_user)
    total_products = await db.products.count_documents({"vendeur_id": vendeur_id})
    total_sales = 0
    total_revenue = 0.0
    cursor = db.products.find({"vendeur_id": vendeur_id})
    async for doc in cursor:
        total_sales += doc.get("salesCount", 0)
        total_revenue += doc.get("price", 0) * doc.get("salesCount", 0)
    return {
        "total_products": total_products,
        "total_sales": total_sales,
        "total_revenue": round(total_revenue, 2),
    }


@router.get("/api/vendeurs/produits/{product_id}")
async def get_vendor_product(
    product_id: str,
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    doc = await _fetch_product(product_id)
    vendeur_id = _get_vendeur_id(current_user)
    _check_ownership(doc, vendeur_id, current_user)
    doc["_id"] = str(doc["_id"])
    return doc


@router.put("/api/vendeurs/produits/{product_id}")
async def update_vendor_product(
    product_id: str,
    data: dict,
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    doc = await _fetch_product(product_id)
    vendeur_id = _get_vendeur_id(current_user)
    _check_ownership(doc, vendeur_id, current_user)

    updates = {}
    if "titre" in data or "name" in data:
        updates["titre"] = _resolve_titre(data)
    if "description" in data:
        updates["description"] = data["description"].strip() if isinstance(data["description"], str) else ""
    if "category" in data:
        updates["category"] = data["category"].strip() if isinstance(data["category"], str) else "Autre"
    if "price" in data:
        updates["price"] = _validate_price(data["price"])
    if "stock" in data:
        updates["stock"] = _validate_stock(data["stock"])
    if "seller_name" in data:
        updates["seller_name"] = data["seller_name"].strip() if isinstance(data["seller_name"], str) else ""
    if "statut" in data:
        if current_user.get("role") == "admin":
            updates["statut"] = data["statut"].strip()
    if "images" in data or "image" in data:
        updates["images"] = _resolve_images(data)
    if "video" in data:
        v = (data["video"] or "").strip()
        if v and not v.startswith(("http://", "https://", "data:")):
            raise HTTPException(400, "L'URL de la vidéo doit commencer par http://, https:// ou data:")
        updates["video"] = v or None
    for field in ["marque", "annee", "transmission", "carburant", "localisation", "couleur", "documents"]:
        if field in data:
            updates[field] = (data[field] or "").strip() if isinstance(data[field], str) else ""
    for field in ["prix_negociable", "livraison", "garantie"]:
        if field in data:
            updates[field] = bool(data[field])
    if "reviews" in data:
        updates["reviews"] = int(data["reviews"]) if str(data["reviews"]).isdigit() else 0
    if "rating" in data:
        try:
            updates["rating"] = float(data["rating"])
        except (TypeError, ValueError):
            pass

    if updates:
        await db.products.update_one({"_id": ObjectId(product_id)}, {"$set": updates})

    doc = await _fetch_product(product_id)
    doc["_id"] = str(doc["_id"])
    return doc


@router.delete("/api/vendeurs/produits/{product_id}")
async def delete_vendor_product(
    product_id: str,
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    doc = await _fetch_product(product_id)
    vendeur_id = _get_vendeur_id(current_user)
    _check_ownership(doc, vendeur_id, current_user)

    await db.products.delete_one({"_id": ObjectId(product_id)})
    return {"message": "Produit supprimé", "id": product_id}


@router.post("/api/vendeurs/produits/upload")
async def upload_vendor_product(
    titre: str = Form(..., min_length=1),
    description: str = Form(""),
    prix: float = Form(...),
    stock: int = Form(0),
    categorie: str = Form("Autre"),
    images: list[UploadFile] = File(default=[]),
    video: UploadFile = File(None),
    current_user: dict = Depends(require_role("vendeur", "admin")),
):
    if prix <= 0:
        raise HTTPException(400, "Le prix doit être supérieur à 0")
    if stock < 0:
        raise HTTPException(400, "Le stock ne peut pas être négatif")

    image_urls = []
    for f in images:
        if not f.filename:
            continue
        if f.content_type not in ALLOWED_IMAGE_TYPES:
            raise HTTPException(400, f"Type d'image non autorisé : {f.content_type}. Formats acceptés : JPEG, PNG, WebP, GIF")
        contents = await f.read()
        if len(contents) > MAX_IMAGE_SIZE:
            raise HTTPException(400, f"L'image {f.filename} dépasse 5 Mo")
        await f.seek(0)

        ext = os.path.splitext(f.filename)[1] or ".jpg"
        name = f"prod_{datetime.utcnow().timestamp()}_{len(image_urls)}{ext}"
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads", "produits", name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as dest:
            shutil.copyfileobj(f.file, dest)
        image_urls.append(f"/uploads/produits/{name}")

    video_url = None
    if video and video.filename:
        if video.content_type not in ALLOWED_VIDEO_TYPES:
            raise HTTPException(400, f"Type vidéo non autorisé : {video.content_type}. Formats : MP4, WebM, OGG, MOV")
        contents = await video.read()
        if len(contents) > MAX_VIDEO_SIZE:
            raise HTTPException(400, "La vidéo dépasse 50 Mo")
        await video.seek(0)
        ext = os.path.splitext(video.filename)[1] or ".mp4"
        vname = f"vid_{datetime.utcnow().timestamp()}{ext}"
        vpath = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads", "produits", vname)
        with open(vpath, "wb") as dest:
            shutil.copyfileobj(video.file, dest)
        video_url = f"/uploads/produits/{vname}"

    vendeur_id = _get_vendeur_id(current_user)
    product = {
        "titre": titre.strip(),
        "description": description.strip(),
        "price": prix,
        "category": categorie.strip(),
        "images": image_urls,
        "video": video_url,
        "vendeur_id": vendeur_id,
        "seller_name": current_user.get("full_name", current_user.get("name", "Vendeur")),
        "rating": 0,
        "stock": stock,
        "salesCount": 0,
        "statut": "publié",
        "date_publication": datetime.utcnow(),
    }
    result = await db.products.insert_one(product)
    product["_id"] = str(result.inserted_id)
    return product
