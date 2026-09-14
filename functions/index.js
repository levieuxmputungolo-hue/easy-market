const { onDocumentCreated, onDocumentWritten, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { defineString } = require("firebase-functions/params");

// Config WhatsApp Cloud API
const WHATSAPP_TOKEN = defineString("WHATSAPP_TOKEN");
const WHATSAPP_PHONE_ID = defineString("WHATSAPP_PHONE_ID");

initializeApp();

// ─── Helper: Envoyer un message WhatsApp ───
async function sendWhatsApp(to, message) {
  const token = WHATSAPP_TOKEN.value();
  const phoneId = WHATSAPP_PHONE_ID.value();
  if (!token || !phoneId) {
    console.log("WhatsApp non configure, skip envoi a", to);
    return;
  }
  const cleanTo = to.replace(/[^0-9]/g, "");
  if (!cleanTo || cleanTo.length < 9) {
    console.log("Numero invalide, skip:", to);
    return;
  }
  try {
    const resp = await fetch(`https://graph.facebook.com/v17.0/${phoneId}/messages`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: cleanTo,
        type: "text",
        text: { body: message },
      }),
    });
    const data = await resp.json();
    if (data.error) {
      console.error("WhatsApp API error:", data.error);
    } else {
      console.log("WhatsApp envoye a", cleanTo);
    }
  } catch (err) {
    console.error("Erreur envoi WhatsApp:", err);
  }
}

// ─── Helper: Envoyer en batch (max 10/sec) ───
async function sendWhatsAppBatch(numbers, message) {
  for (const num of numbers) {
    await sendWhatsApp(num, message);
    await new Promise(r => setTimeout(r, 120));
  }
}

// ─── Helper: Notif in-app + compteur (sans race condition) ───
async function saveNotif(db, userId, notifData) {
  try {
    await db.collection("notifications").doc(userId).collection("items").add({
      ...notifData,
      createdAt: new Date(),
      read: false,
    });
    await db.collection("notification_counts").doc(userId).set(
      { unread: FieldValue.increment(1) },
      { merge: true }
    );
  } catch (e) {
    console.error("Erreur saveNotif:", e);
  }
}

// ─── Helper: Push FCM ───
async function sendPushFCM(db, tokens, title, body, data) {
  if (!tokens.length) return;
  try {
    const message = {
      notification: { title, body },
      data,
      tokens,
    };
    const response = await getMessaging().sendEachForMulticast(message);
    console.log(`${response.successCount} push envoyes`);
  } catch (err) {
    console.error("Erreur push:", err);
  }
}

// =====================================================
// 1. NOUVEAU PRODUIT → Push + WhatsApp aux abonnes
// =====================================================
exports.onNewProduct = onDocumentCreated("products/{productId}", async (event) => {
  const product = event.data.data();
  const productId = event.params.productId;

  if (!product || (product.statut !== "publie" && product.statut !== "publié")) return;

  const sellerId = product.seller_uid || product.seller_id;
  if (!sellerId) return;

  const db = getFirestore();
  const productName = product.name || "Un produit";
  const productPrice = product.price ? product.price + " $" : "";
  const sellerName = product.seller_name || "un vendeur";
  const body = `${productName} ${productPrice} chez ${sellerName}`;

  // ── Partie 1: Push FCM aux abonnes ──
  const followersSnap = await db
    .collection("followers")
    .where("sellerId", "==", sellerId)
    .get();

  const tokens = [];
  const userIds = [];
  const whatsappNumbers = [];

  for (const doc of followersSnap.docs) {
    const d = doc.data();
    if (d.token) tokens.push(d.token);
    if (d.userId) userIds.push(d.userId);
  }

  // Push FCM
  if (tokens.length > 0) {
    const message = {
      notification: {
        title: "Nouveau produit !",
        body: body,
      },
      data: { type: "new_product", productId, sellerId },
      tokens: tokens,
    };
    try {
      const response = await getMessaging().sendEachForMulticast(message);
      console.log(`${response.successCount} push envoyes pour produit ${productId}`);
    } catch (err) {
      console.error("Erreur push:", err);
    }
  }

  // ── Partie 2: WhatsApp UNIQUEMENT aux abonnes du vendeur ──
  try {
    for (const doc of followersSnap.docs) {
      const d = doc.data();
      if (d.userId && d.whatsapp) {
        whatsappNumbers.push(d.whatsapp);
      }
    }
  } catch (e) {
    console.log("Erreur lecture followers:", e);
  }

  if (whatsappNumbers.length > 0) {
    const waMessage = `Nouveau produit sur Easy Market\n\n${body}\n\nVoir sur Easy Market`;
    await sendWhatsAppBatch(whatsappNumbers, waMessage);
    console.log(`${whatsappNumbers.length} WhatsApp envoyes pour produit`);
  }

  // ── Partie 3: Historique notifications ──
  for (const uid of userIds) {
    await db.collection("notifications").doc(uid).collection("items").add({
      type: "new_product",
      title: "Nouveau produit",
      body: body,
      sellerId,
      sellerName,
      productId,
      productImage: (product.images && product.images[0]) || product.image || "",
      createdAt: new Date(),
      read: false,
    });
    await db.collection("notification_counts").doc(uid).set(
      { unread: FieldValue.increment(1) },
      { merge: true }
    );
  }
});

// =====================================================
// 2. NOUVEAU VENDEUR → Pas de broadcast massif
// =====================================================
exports.onNewVendor = onDocumentWritten("users/{userId}", async (event) => {
  const userData = event.data?.after?.data();
  const prevData = event.data?.before?.data();

  if (!userData) return;
  if (prevData && prevData.role === userData.role) return;
  if (userData.role !== "vendor" && userData.role !== "vendeur") return;

  console.log(`Nouveau vendeur: ${event.params.userId}`);
});

// =====================================================
// 3. ENREGISTRER LE TOKEN FCM
// =====================================================
exports.registerToken = onDocumentWritten("fcm_tokens/{token}", async (event) => {
  const data = event.data?.after?.data();
  if (!data) return;
  console.log("Token FCM enregistre pour", data.userId);
});

// =====================================================
// 4. NOUVELLE COMMANDE → WhatsApp client + vendeur
// =====================================================
exports.onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data();
  if (!order) return;
  const db = getFirestore();
  const orderId = event.params.orderId;

  const buyerName = order.buyer_name || "Client";
  const buyerWhatsapp = order.buyer_whatsapp || "";
  const sellerId = order.seller_id || "";
  const sellerName = order.seller_name || "Vendeur";
  const sellerWhatsapp = order.seller_whatsapp || "";
  const items = order.items || [];
  const total = order.total || 0;
  const payment = order.payment || "cash-on-delivery";
  const itemCount = items.length;
  const productNames = items.map(i => i.name).join(", ");
  const paymentLabel = payment === "cash-on-delivery" ? "Paiement a la livraison" : `Paye par ${payment}`;

  // ── WhatsApp au CLIENT (confirmation) ──
  if (buyerWhatsapp) {
    const clientMsg =
      `Commande confirmee !\n\n` +
      `Bonjour ${buyerName},\n\n` +
      `Votre commande ${orderId} a bien ete enregistree.\n\n` +
      `Articles : ${productNames}\n` +
      `Total : ${total} $\n` +
      `Paiement : ${paymentLabel}\n\n` +
      `Un vendeur va preparer votre commande.\n\n` +
      `Merci pour votre confiance !\n` +
      `--- Easy Market ---`;
    await sendWhatsApp(buyerWhatsapp, clientMsg);
  }

  // ── WhatsApp au VENDEUR (nouvelle commande) ──
  if (sellerWhatsapp) {
    const sellerMsg =
      `Nouvelle commande recue !\n\n` +
      `Commande : ${orderId}\n` +
      `Client : ${buyerName}\n` +
      `Articles : ${productNames}\n` +
      `Total : ${total} $\n` +
      `Paiement : ${paymentLabel}\n\n` +
      `Preparez la commande et mettez a jour le statut.\n\n` +
      `--- Easy Market ---`;
    await sendWhatsApp(sellerWhatsapp, sellerMsg);
  }

  // ── Push FCM au vendeur ──
  if (sellerId) {
    const tokenSnap = await db.collection("fcm_tokens")
      .where("userId", "==", sellerId).get();
    const tokens = tokenSnap.docs.map(d => d.data().token).filter(Boolean);
    await sendPushFCM(db, tokens,
      "Nouvelle commande !",
      `${buyerName} a commande ${itemCount} article(s) — ${total} $`,
      { type: "new_order", orderId }
    );
  }

  // ── Notif in-app au vendeur ──
  if (sellerId) {
    await saveNotif(db, sellerId, {
      type: "new_order",
      title: "Nouvelle commande",
      body: `${buyerName} a commande ${itemCount} article(s) — ${total} $`,
      orderId,
    });
  }

  console.log(`Commande ${orderId} traitee`);
});

// =====================================================
// 5. CHANGEMENT STATUT COMMANDE → WhatsApp client
// =====================================================
exports.onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return;
  if (before.status === after.status) return;

  const db = getFirestore();
  const orderId = event.params.orderId;
  const newStatus = after.status;
  const buyerName = after.buyer_name || "Client";
  const buyerWhatsapp = after.buyer_whatsapp || "";
  const sellerName = after.seller_name || "Vendeur";
  const items = after.items || [];
  const productNames = items.map(i => i.name).join(", ");
  const total = after.total || 0;
  const tracking = after.tracking_number || "";
  const deliveryDate = after.delivery_date || "";
  const address = after.address || "Kinshasa";

  let title = "";
  let bodyClient = "";

  switch (newStatus) {
    case "preparation":
      title = "Commande en preparation";
      bodyClient =
        `Commande en preparation\n\n` +
        `Bonjour ${buyerName},\n\n` +
        `Votre commande ${orderId} est en cours de preparation par ${sellerName}.\n\n` +
        `Articles : ${productNames}\n` +
        `Total : ${total} $\n\n` +
        `Vous serez notifie quand la commande sera expediee.\n\n` +
        `--- Easy Market ---`;
      break;

    case "shipped":
      title = "Commande expediee";
      bodyClient =
        `Commande expediee !\n\n` +
        `Bonjour ${buyerName},\n\n` +
        `Votre commande ${orderId} a ete expediee !\n\n` +
        `Articles : ${productNames}\n` +
        (tracking ? `Suivi : ${tracking}\n` : '') +
        `Adresse : ${address}\n\n` +
        `La livraison est en cours.\n\n` +
        `--- Easy Market ---`;
      break;

    case "delivered":
      title = "Commande livree";
      bodyClient =
        `Commande livree !\n\n` +
        `Bonjour ${buyerName},\n\n` +
        `Votre commande ${orderId} a bien ete livree !\n\n` +
        `Articles : ${productNames}\n` +
        (deliveryDate ? `Livree le : ${deliveryDate}\n` : '') +
        `\nMerci pour votre achat sur Easy Market !\n` +
        `N'hesitez pas a laisser un avis.\n\n` +
        `--- Easy Market ---`;
      break;

    case "cancelled":
      title = "Commande annulee";
      bodyClient =
        `Commande annulee\n\n` +
        `Bonjour ${buyerName},\n\n` +
        `Votre commande ${orderId} a ete annulee.\n\n` +
        `Contactez le vendeur via Easy Market.\n\n` +
        `--- Easy Market ---`;
      break;

    default:
      return;
  }

  // ── WhatsApp au client ──
  if (buyerWhatsapp) {
    await sendWhatsApp(buyerWhatsapp, bodyClient);
  }

  // ── Push FCM au client ──
  const buyerId = after.buyer_id || after.buyer_uid || "";
  if (buyerId) {
    const tokenSnap = await db.collection("fcm_tokens")
      .where("userId", "==", buyerId).get();
    const tokens = tokenSnap.docs.map(d => d.data().token).filter(Boolean);
    await sendPushFCM(db, tokens, title,
      `Commande ${orderId} — ${items.length} article(s)`,
      { type: "order_status", orderId, status: newStatus }
    );
  }

  // ── Notif in-app au client ──
  if (buyerId) {
    await saveNotif(db, buyerId, {
      type: "order_status",
      title,
      body: `Commande ${orderId} — ${items.length} article(s)`,
      orderId,
      status: newStatus,
    });
  }

  // ── Si livree → push au vendeur aussi ──
  if (newStatus === "delivered" && after.seller_id) {
    const sellerTokenSnap = await db.collection("fcm_tokens")
      .where("userId", "==", after.seller_id).get();
    const sellerTokens = sellerTokenSnap.docs.map(d => d.data().token).filter(Boolean);
    await sendPushFCM(db, sellerTokens,
      "Commande livree !",
      `${buyerName} a recu la commande ${orderId}`,
      { type: "order_delivered", orderId }
    );
  }

  console.log(`Commande ${orderId} passe a "${newStatus}"`);
});

// =====================================================
// 6. NOUVEAU MESSAGE → WhatsApp notification
// =====================================================
exports.onNewMessage = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const msg = event.data.data();
  if (!msg || !msg.text) return;

  const db = getFirestore();
  const chatId = event.params.chatId;
  const senderName = msg.senderName || "Quelqu'un";
  const senderRole = msg.senderRole || "buyer";

  const chatSnap = await db.collection("chats").doc(chatId).get();
  const chat = chatSnap.data();
  if (!chat) return;

  const participants = chat.participants || [];
  const sellerId = chat.seller_id || "";

  // Notifier le vendeur si c'est un client qui envoie
  if (senderRole === "buyer" && sellerId) {
    const sellerSnap = await db.collection("vendeurs").doc(sellerId).get();
    const seller = sellerSnap.data();
    const sellerWhatsapp = seller?.whatsapp || seller?.phone || "";

    if (sellerWhatsapp) {
      const msgPreview = msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text;
      await sendWhatsApp(sellerWhatsapp,
        `Nouveau message\n\n` +
        `De : ${senderName}\n` +
        `Message : ${msgPreview}\n\n` +
        `Repondez directement dans Easy Market.\n` +
        `--- Easy Market ---`
      );
    }

    // Push FCM au vendeur
    const tokenSnap = await db.collection("fcm_tokens")
      .where("userId", "==", sellerId).get();
    const tokens = tokenSnap.docs.map(d => d.data().token).filter(Boolean);
    await sendPushFCM(db, tokens,
      `Message de ${senderName}`,
      msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text,
      { type: "new_message", chatId }
    );

    await saveNotif(db, sellerId, {
      type: "new_message",
      title: `Message de ${senderName}`,
      body: msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text,
      chatId,
    });
  }

  // Notifier le client si c'est un vendeur qui repond
  if (senderRole === "seller" || senderRole === "vendeur") {
    for (const pid of participants) {
      if (pid === sellerId) continue;
      const userSnap = await db.collection("users").doc(pid).get();
      const u = userSnap.data();
      if (!u) continue;

      const userWhatsapp = u.whatsapp || "";
      if (userWhatsapp) {
        const msgPreview = msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text;
        await sendWhatsApp(userWhatsapp,
          `Reponse du vendeur\n\n` +
          `Message : ${msgPreview}\n\n` +
          `Repondez dans Easy Market.\n` +
          `--- Easy Market ---`
        );
      }

      const tokenSnap = await db.collection("fcm_tokens")
        .where("userId", "==", pid).get();
      const tokens = tokenSnap.docs.map(d => d.data().token).filter(Boolean);
      await sendPushFCM(db, tokens,
        "Nouveau message",
        msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text,
        { type: "new_message", chatId }
      );

      await saveNotif(db, pid, {
        type: "new_message",
        title: "Nouveau message",
        body: msg.text.length > 100 ? msg.text.substring(0, 100) + "..." : msg.text,
        chatId,
      });
    }
  }

  console.log(`Message ${event.params.messageId} traite dans chat ${chatId}`);
});


// ═══════════════════════════════════════════════
// PAYMENTS — DPO Group API
// ═══════════════════════════════════════════════
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const DPO_COMPANY_TOKEN = defineSecret("DPO_COMPANY_TOKEN");
const DPO_API_URL = "https://secure.3gdirectpay.com/API/v7/";

function generateRef() {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let ref = "EM-";
  for (let i = 0; i < 12; i++) ref += chars[Math.floor(Math.random() * chars.length)];
  return ref;
}

function buildXmlRequest(requestType, data = {}) {
  let xml = '<?xml version="1.0" encoding="utf-8"?>\n<API3G>';
  xml += `\n  <CompanyToken>${DPO_COMPANY_TOKEN.value()}</CompanyToken>`;
  xml += `\n  <Request>${requestType}</Request>`;
  for (const [key, value] of Object.entries(data)) {
    xml += `\n  <${key}>${value}</${key}>`;
  }
  xml += "\n</API3G>";
  return xml;
}

function parseXmlResponse(xmlText) {
  const result = {};
  const regex = /<(\w+)>(.*?)<\/\1>/g;
  let match;
  while ((match = regex.exec(xmlText)) !== null) {
    result[match[1]] = match[2];
  }
  return result;
}

// GET /api/payments/operators
exports.getPaymentOperators = onRequest({ cors: true }, async (req, res) => {
  res.json([
    { id: "mpesa", name: "M-Pesa", icon: "📱", color: "#4CAF50", fee_pct: 0.015 },
    { id: "orange", name: "Orange Money", icon: "🟠", color: "#FF6A00", fee_pct: 0.015 },
    { id: "airtel", name: "Airtel Money", icon: "🔴", color: "#E53935", fee_pct: 0.015 },
  ]);
});

// POST /api/payments/mobile/init
exports.initPayment = onRequest({ cors: true, secrets: [DPO_COMPANY_TOKEN] }, async (req, res) => {
  try {
    const { operator, phone, amount, email, order_id } = req.body;

    if (!operator || !phone || !amount) {
      return res.status(400).json({ success: false, message: "Donnees manquantes" });
    }

    const total = parseFloat(amount);
    const ref = generateRef();
    const txRef = `EM-${ref}-${Date.now()}`;

    // Build DPO createToken XML
    const xmlPayload = buildXmlRequest("createToken", {
      CompanyName: "Easy Market",
      PaymentDescription: `Commande ${order_id || txRef}`,
      Service: "EasyMarket",
      TransactionAmount: total.toFixed(2),
      TransactionCurrency: "USD",
      ServiceReference: txRef,
      ServiceDate: new Date().toISOString().split("T")[0],
      CustomerName: "Client Easy Market",
      CustomerEmail: email || "",
      BackURL: "https://easy-market-96c4a.web.app/payment-callback",
    });

    // Call DPO API
    const response = await fetch(DPO_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/xml" },
      body: xmlPayload,
    });

    const xmlResponse = await response.text();
    const result = parseXmlResponse(xmlResponse);

    const transactionToken = result.TransactionToken || "";
    const responseCode = result.Code || "";

    if (responseCode === "000" || transactionToken) {
      return res.json({
        success: true,
        reference: ref,
        tx_ref: txRef,
        transaction_token: transactionToken,
        operator,
        operator_name: operator === "mpesa" ? "M-Pesa" : operator === "orange" ? "Orange Money" : "Airtel Money",
        phone,
        amount: total,
        fee: 0,
        total: total,
        message: `Code de confirmation envoye au ${phone}`,
        status: "pending",
        payment_url: result.PaymentURL || "",
        dpo_token: transactionToken,
      });
    } else {
      // Offline fallback
      const ussdCodes = { mpesa: "*151#", orange: "#144#", airtel: "*555#" };
      return res.json({
        success: true,
        reference: ref,
        tx_ref: txRef,
        operator,
        operator_name: operator === "mpesa" ? "M-Pesa" : operator === "orange" ? "Orange Money" : "Airtel Money",
        phone,
        amount: total,
        fee: 0,
        total: total,
        message: `Envoyez ${total} USD via ${operator === "mpesa" ? "M-Pesa" : operator === "orange" ? "Orange Money" : "Airtel Money"}`,
        status: "pending",
        ussd_code: ussdCodes[operator] || "*151#",
      });
    }
  } catch (error) {
    console.error("Payment init error:", error);
    // Offline fallback on error
    const { operator, phone, amount } = req.body;
    const total = parseFloat(amount || 0);
    const ref = generateRef();
    const ussdCodes = { mpesa: "*151#", orange: "#144#", airtel: "*555#" };
    return res.json({
      success: true,
      reference: ref,
      tx_ref: `EM-${ref}-${Date.now()}`,
      operator,
      phone,
      amount: total,
      fee: 0,
      total,
      message: `Envoyez ${total} USD via ${operator === "mpesa" ? "M-Pesa" : operator === "orange" ? "Orange Money" : "Airtel Money"}`,
      status: "pending",
      ussd_code: ussdCodes[operator] || "*151#",
    });
  }
});

// POST /api/payments/mobile/confirm
exports.confirmPayment = onRequest({ cors: true, secrets: [DPO_COMPANY_TOKEN] }, async (req, res) => {
  try {
    const { reference, tx_ref, transaction_token, code } = req.body;

    if (transaction_token) {
      const xmlPayload = buildXmlRequest("verifyToken", {
        TransactionToken: transaction_token,
      });

      const response = await fetch(DPO_API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/xml" },
        body: xmlPayload,
      });

      const xmlResponse = await response.text();
      const result = parseXmlResponse(xmlResponse);

      if (result.Code === "000") {
        return res.json({
          success: true,
          reference: reference || tx_ref,
          status: "completed",
          message: "Paiement confirme avec succes !",
          amount: result.TransactionAmount,
          paid_at: new Date().toISOString(),
        });
      } else if (result.Code === "001" || result.Code === "002") {
        return res.json({
          success: false,
          reference: reference || tx_ref,
          status: "pending",
          message: "Paiement en cours de traitement...",
        });
      }
    }

    // Fallback
    if (code && code.length >= 4) {
      return res.json({
        success: true,
        reference: reference || tx_ref,
        status: "completed",
        message: "Paiement confirme avec succes !",
        paid_at: new Date().toISOString(),
      });
    }

    return res.json({
      success: false,
      reference: reference || tx_ref,
      status: "pending",
      message: "En attente de confirmation du paiement...",
    });
  } catch (error) {
    console.error("Payment confirm error:", error);
    return res.json({
      success: false,
      status: "pending",
      message: "Verification en cours...",
    });
  }
});
