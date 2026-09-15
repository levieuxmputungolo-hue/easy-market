from fastapi import APIRouter, HTTPException, Depends, Request
from app.auth import get_current_user
from datetime import datetime
import random, string, os
import httpx

router = APIRouter()

# Flutterwave config
FLW_SECRET_KEY = os.getenv("FLW_SECRET_KEY", "")
FLW_PUBLIC_KEY = os.getenv("FLW_PUBLIC_KEY", "")
FLW_API_URL = "https://api.flutterwave.com/v3"

# Supported operators in DRC via Flutterwave
OPERATORS = {
    "mpesa": {
        "name": "M-Pesa",
        "icon": "📱",
        "color": "#4CAF50",
        "flw_method": "mobilemoney",
        "flw_network": "vodacom",
        "country": "CD",
        "prefixes": ["+24381", "+24382", "+24383", "+24384", "+24385"],
        "fee_pct": 0.015,
    },
    "orange": {
        "name": "Orange Money",
        "icon": "🟠",
        "color": "#FF6A00",
        "flw_method": "mobilemoney",
        "flw_network": "orange",
        "country": "CD",
        "prefixes": ["+24389", "+24388", "+24390"],
        "fee_pct": 0.015,
    },
    "airtel": {
        "name": "Airtel Money",
        "icon": "🔴",
        "color": "#E53935",
        "flw_method": "mobilemoney",
        "flw_network": "airtel",
        "country": "CD",
        "prefixes": ["+24397", "+24398", "+24399"],
        "fee_pct": 0.015,
    },
}


def generate_ref():
    return "EM-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=12))


def generate_order_id():
    return "ORD-" + str(int(datetime.utcnow().timestamp()))


def get_ussd_code(operator: str) -> str:
    return {"mpesa": "*151#", "orange": "#144#", "airtel": "*555#"}.get(operator, "*151#")


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
async def init_payment(data: dict, current_user: dict = Depends(get_current_user)):
    operator = data.get("operator", "")
    phone = data.get("phone", "")
    amount = float(data.get("amount", 0))
    email = data.get("email", current_user.get("email", ""))
    order_id = data.get("order_id", generate_order_id())

    if operator not in OPERATORS:
        raise HTTPException(400, "Operateur non supporte")
    if not phone or len(phone) < 10:
        raise HTTPException(400, "Numero de telephone invalide")
    if amount <= 0:
        raise HTTPException(400, "Le montant doit etre superieur a 0")

    op = OPERATORS[operator]
    fee = round(amount * op["fee_pct"], 2)
    total = round(amount + fee, 2)
    ref = generate_ref()
    tx_ref = f"EM-{ref}-{int(datetime.utcnow().timestamp())}"

    if not FLW_SECRET_KEY:
        # Offline fallback — no API key
        return {
            "success": True,
            "reference": ref,
            "tx_ref": tx_ref,
            "operator": operator,
            "operator_name": op["name"],
            "phone": phone,
            "amount": amount,
            "fee": fee,
            "total": total,
            "message": f"Envoyez {total} USD via {op['name']} au {phone}",
            "status": "pending",
            "ussd_code": get_ussd_code(operator),
        }

    # Flutterwave payment init
    payload = {
        "tx_ref": tx_ref,
        "amount": str(total),
        "currency": "USD",
        "email": email,
        "phone_number": phone,
        "network": op["flw_network"],
        "redirect_url": "https://easy-market-96c4a.web.app/payment-callback",
        "meta": {
            "order_id": order_id,
            "operator": operator,
        },
    }

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{FLW_API_URL}/payments",
                json=payload,
                headers={
                    "Authorization": f"Bearer {FLW_SECRET_KEY}",
                    "Content-Type": "application/json",
                },
                timeout=30.0,
            )
            result = response.json()

        if result.get("status") == "success":
            return {
                "success": True,
                "reference": ref,
                "tx_ref": tx_ref,
                "operator": operator,
                "operator_name": op["name"],
                "phone": phone,
                "amount": amount,
                "fee": fee,
                "total": total,
                "message": f"Code de confirmation envoye au {phone}",
                "status": "pending",
                "payment_url": result.get("data", {}).get("link", ""),
                "flw_id": result.get("data", {}).get("id"),
            }
        else:
            return {
                "success": False,
                "message": result.get("message", "Erreur Flutterwave"),
                "status": "failed",
            }

    except httpx.TimeoutException:
        # Offline fallback
        return {
            "success": True,
            "reference": ref,
            "tx_ref": tx_ref,
            "operator": operator,
            "operator_name": op["name"],
            "phone": phone,
            "amount": amount,
            "fee": fee,
            "total": total,
            "message": f"Envoyez {total} USD via {op['name']} au {phone}",
            "status": "pending",
            "ussd_code": get_ussd_code(operator),
        }
    except Exception as e:
        raise HTTPException(500, f"Erreur de connexion: {str(e)}")


@router.post("/api/payments/mobile/confirm")
async def confirm_payment(data: dict, current_user: dict = Depends(get_current_user)):
    reference = data.get("reference", "")
    tx_ref = data.get("tx_ref", "")
    code = data.get("code", "")

    if not reference and not tx_ref:
        raise HTTPException(400, "Reference invalide")

    if not FLW_SECRET_KEY:
        # Offline fallback
        if code and len(code) >= 4:
            return {
                "success": True,
                "reference": reference or tx_ref,
                "status": "completed",
                "message": "Paiement confirme avec succes !",
                "paid_at": datetime.utcnow().isoformat(),
            }
        return {
            "success": False,
            "reference": reference or tx_ref,
            "status": "pending",
            "message": "En attente de confirmation du paiement...",
        }

    # Flutterwave verification
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{FLW_API_URL}/transactions/verify",
                params={"tx_ref": tx_ref},
                headers={
                    "Authorization": f"Bearer {FLW_SECRET_KEY}",
                },
                timeout=30.0,
            )
            result = response.json()

        if result.get("status") == "success":
            tx = result.get("data", {})
            status = tx.get("status", "")
            if status == "successful":
                return {
                    "success": True,
                    "reference": reference or tx_ref,
                    "status": "completed",
                    "message": "Paiement confirme avec succes !",
                    "amount": tx.get("amount"),
                    "paid_at": tx.get("created_at"),
                    "flw_id": tx.get("id"),
                }
            elif status == "pending":
                return {
                    "success": False,
                    "reference": reference or tx_ref,
                    "status": "pending",
                    "message": "Paiement en cours de traitement...",
                }
            else:
                return {
                    "success": False,
                    "reference": reference or tx_ref,
                    "status": "failed",
                    "message": "Paiement non confirme",
                }
    except Exception:
        pass

    return {
        "success": False,
        "reference": reference or tx_ref,
        "status": "pending",
        "message": "En attente de confirmation du paiement...",
    }


@router.post("/api/payments/webhook")
async def flutterwave_webhook(request: Request):
    """Flutterwave webhook for payment status updates."""
    from app.database import db

    body = await request.json()
    event = body.get("event", "")
    data = body.get("data", {})

    if event == "charge.completed" and data.get("status") == "successful":
        tx_ref = data.get("tx_ref", "")
        amount = data.get("amount", 0)
        flw_id = data.get("id", "")

        # Update order status in MongoDB
        if tx_ref:
            await db.orders.update_one(
                {"order_id": tx_ref},
                {"$set": {"status": "paye", "payment_confirmed": True, "flw_id": str(flw_id), "paid_at": datetime.utcnow()}},
            )
            print(f"Flutterwave Payment confirmed: tx_ref={tx_ref}, amount={amount}")

        return {"status": "ok"}

    return {"status": "ignored"}
