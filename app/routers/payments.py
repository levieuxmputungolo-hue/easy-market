from fastapi import APIRouter, HTTPException
from datetime import datetime
import random, string

router = APIRouter()

OPERATORS = {
    "mpesa": {
        "name": "M-Pesa",
        "icon": "📱",
        "color": "#4CAF50",
        "prefixes": ["+24381", "+24382", "+24383", "+24384", "+24385"],
        "fee_pct": 0.085,
    },
    "orange": {
        "name": "Orange Money",
        "icon": "🟠",
        "color": "#FF6A00",
        "prefixes": ["+24389", "+24388", "+24390"],
        "fee_pct": 0.09,
    },
    "airtel": {
        "name": "Airtel Money",
        "icon": "🔴",
        "color": "#E53935",
        "prefixes": ["+24397", "+24398", "+24399"],
        "fee_pct": 0.095,
    },
}

def generate_ref():
    return "PAY-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=12))

@router.get("/api/payments/operators")
async def get_operators():
    return [
        {
            "id": k,
            "name": v["name"],
            "icon": v["icon"],
            "color": v["color"],
            "fee_pct": v["fee_pct"],
        }
        for k, v in OPERATORS.items()
    ]

@router.post("/api/payments/mobile/init")
async def init_payment(data: dict):
    operator = data.get("operator", "")
    phone = data.get("phone", "")
    amount = float(data.get("amount", 0))

    if operator not in OPERATORS:
        raise HTTPException(400, "Opérateur non supporté")
    if not phone or len(phone) < 10:
        raise HTTPException(400, "Numéro de téléphone invalide")
    if amount <= 0:
        raise HTTPException(400, "Le montant doit être supérieur à 0")

    op = OPERATORS[operator]
    fee = round(amount * op["fee_pct"], 2)
    total = round(amount + fee, 2)

    ref = generate_ref()

    return {
        "success": True,
        "reference": ref,
        "operator": operator,
        "operator_name": op["name"],
        "phone": phone,
        "amount": amount,
        "fee": fee,
        "total": total,
        "message": f"Code de confirmation envoyé au {phone}",
        "status": "pending",
    }

@router.post("/api/payments/mobile/confirm")
async def confirm_payment(data: dict):
    reference = data.get("reference", "")
    code = data.get("code", "")

    if not reference:
        raise HTTPException(400, "Référence invalide")
    if not code or len(code) < 4:
        raise HTTPException(400, "Code de confirmation invalide")

    # Simulate confirmation (always success in demo)
    return {
        "success": True,
        "reference": reference,
        "status": "completed",
        "message": "Paiement confirmé avec succès !",
        "paid_at": datetime.utcnow().isoformat(),
    }
