from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

class Product(BaseModel):
    name: str
    description: str
    price: float
    category: str
    image: Optional[str] = ""
    seller_id: str
    seller_name: str
    rating: float = 0
    stock: int = 0
    salesCount: int = 0
    created_at: Optional[datetime] = None

class ProductCreate(BaseModel):
    titre: str = Field(..., min_length=1, max_length=200)
    description: str = Field("", max_length=5000)
    price: float = Field(..., gt=0)
    category: str = Field("Autre", max_length=100)
    images: List[str] = []
    video: Optional[str] = None
    seller_name: str = Field("Vendeur", max_length=200)
    stock: int = Field(0, ge=0)
    marque: str = Field("", max_length=100)
    annee: str = Field("", max_length=10)
    transmission: str = Field("", max_length=50)
    carburant: str = Field("", max_length=50)
    localisation: str = Field("", max_length=200)
    couleur: str = Field("", max_length=50)
    documents: str = Field("", max_length=200)
    prix_negociable: bool = False
    livraison: bool = False
    garantie: bool = False

class ProductUpdate(BaseModel):
    titre: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=5000)
    price: Optional[float] = Field(None, gt=0)
    category: Optional[str] = Field(None, max_length=100)
    images: Optional[List[str]] = None
    video: Optional[str] = None
    seller_name: Optional[str] = Field(None, max_length=200)
    stock: Optional[int] = Field(None, ge=0)
    statut: Optional[str] = None
    marque: Optional[str] = Field(None, max_length=100)
    annee: Optional[str] = Field(None, max_length=10)
    transmission: Optional[str] = Field(None, max_length=50)
    carburant: Optional[str] = Field(None, max_length=50)
    localisation: Optional[str] = Field(None, max_length=200)
    couleur: Optional[str] = Field(None, max_length=50)
    documents: Optional[str] = Field(None, max_length=200)
    prix_negociable: Optional[bool] = None
    livraison: Optional[bool] = None
    garantie: Optional[bool] = None

class OrderItem(BaseModel):
    product_id: str
    quantity: int = Field(..., gt=0)
    price: Optional[float] = Field(None, ge=0)

class Order(BaseModel):
    user_id: str
    items: List[OrderItem]
    total: float = Field(..., gt=0)
    status: str = "pending"
    created_at: Optional[datetime] = None

class User(BaseModel):
    email: str
    password: str
    name: str
    phone: Optional[str] = ""
    created_at: Optional[datetime] = None
