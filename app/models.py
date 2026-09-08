from pydantic import BaseModel
from typing import Optional
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
    created_at: datetime = None

class User(BaseModel):
    email: str
    password: str
    name: str
    phone: Optional[str] = ""
    created_at: datetime = None

class Order(BaseModel):
    user_id: str
    items: list
    total: float
    status: str = "pending"
    created_at: datetime = None
