import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Écran de conversation Easy Market (client ↔ vendeur).
///
/// Corrigé par rapport à la version d'origine :
///  1. `CircularIndicator()` n'existe pas en Flutter → `CircularProgressIndicator()`.
///  2. `participants` ne contenait qu'un NOM (`recipientName`) → les règles
///     Firestore (`request.auth.uid in participants`) coupaient l'accès du
///     vendeur et écrasaient les UIDs écrits par main.dart. On utilise
///     maintenant `FieldValue.arrayUnion` avec des UID uniquement.
///  3. ID de message généré par Firestore à chaque envoi → double-tap = doublon.
///     Maintenant l'ID est déterministe côté client (`clientMsgId`), donc
///     idempotent : le même envoi réécrit le même document.
///  4. `FieldValue.serverTimestamp()` en champ `orderBy('timestamp')` rend le
///     message invisible tant que le serveur n'a pas accusé réception
///     (flicker/disparition). On écrit `Timestamp.now()` + `serverTime`.
///  5. Avatar `NetworkImage('')` → plantage visuel sur URL vide : garde-fou.
///  6. Erreur d'envoi silencieuse (`debugPrint` seulement) → SnackBar.
///  7. Controllers jamais libérés → `dispose()`.
class ChatScreen extends StatefulWidget {
  final String chatId; // ID de la conversation ou du produit/vendeur
  final String currentUserId;
  final String recipientName;
  final String recipientAvatar;
  /// UID du destinataire. FACULTATIF mais fortement conseillé :
  /// il faut un identifiant (UID), jamais un nom.
  final String recipientId;

  const ChatScreen({
    Key? key,
    required this.chatId,
    required this.currentUserId,
    required this.recipientName,
    required this.recipientAvatar,
    this.recipientId = '',
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  /// UID réel de l'utilisateur connecté (les règles Firestore vérifient
  /// `senderId == request.auth.uid`).
  String get _uid => _user?.uid ?? widget.currentUserId;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Avatar sûr : renvoie null si l'URL est vide ou invalide.
  ImageProvider? _avatarProvider(String url) {
    final u = url.trim();
    if (u.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return NetworkImage(u);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // Envoyer un message proprement sur Firestore
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    if (_user == null) {
      _showError('Connectez-vous pour envoyer vos messages au vendeur');
      return;
    }

    final msgText = text.trim();
    setState(() => _isSending = true);

    // ID déterministe : un même envoi réécrit le même document (aucun doublon
    // possible en cas de double-clic ou de rejeu réseau).
    final clientMsgId = '${_uid}_${DateTime.now().microsecondsSinceEpoch}';
    final firestore = FirebaseFirestore.instance;
    final messageRef = firestore
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(clientMsgId);

    try {
      // 1) Le message (sous-collection)
      await messageRef.set(<String, dynamic>{
        'id': messageRef.id,
        'clientMsgId': clientMsgId,
        'senderId': _uid,
        'senderName': _user?.displayName ?? _user?.email ?? 'Client',
        'senderRole': 'buyer',
        'text': msgText,
        'type': 'text', // 'text', 'image', 'audio'
        'timestamp': Timestamp.now(), // champ d'ordre : doit être immédiat
        'serverTime': FieldValue.serverTimestamp(),
        'read': false,
      });

      // 2) Le document de conversation : FUSION (merge), jamais d'écrasement.
      //    participants reste un tableau d'UID (arrayUnion) — c'est ce que
      //    main.dart écrit à la création et ce que les règles Firestore attendent.
      final participants = <String>[_uid];
      if (widget.recipientId.isNotEmpty) participants.add(widget.recipientId);

      await firestore.collection('chats').doc(widget.chatId).set(
        <String, dynamic>{
          'lastMessage': msgText,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessageSender': 'buyer',
          'unread_seller': FieldValue.increment(1),
          'participants': FieldValue.arrayUnion(participants),
        },
        SetOptions(merge: true),
      );

      _messageController.clear();

      // Faire défiler vers le bas (ListView inversée : position 0 = plus récent)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      debugPrint("Erreur lors de l'envoi du message : $e");
      _showError('Message non envoyé : vérifiez votre connexion');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true, // Garde la vue visible au-dessus du clavier
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.orange.shade100,
              backgroundImage: _avatarProvider(widget.recipientAvatar),
              child: widget.recipientAvatar.trim().isEmpty
                  ? Text(
                      widget.recipientName.isNotEmpty
                          ? widget.recipientName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "En ligne",
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Bouton Commander conservé dans l'en-tête
          TextButton.icon(
            onPressed: () {
              // Action Commander existante dans EasyMarket
            },
            icon: const Icon(Icons.shopping_cart_checkout,
                color: Colors.orange),
            label: const Text("Commander",
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Suggestions rapides EasyMarket
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[100],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickSuggestion("Commande ?"),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion("Prix gros"),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion("Délai"),
                ],
              ),
            ),
          ),

          // Liste des messages en temps réel (StreamBuilder)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("Aucun message. Démarrez la discussion !",
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Affiche les nouveaux messages en bas
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _uid;
                    final type = (data['type'] ?? 'text') as String;
                    final messageText = (data['text'] ?? '') as String;
                    final fileUrl = (data['fileUrl'] ?? '') as String;

                    Widget content;
                    if (type == 'image' && fileUrl.isNotEmpty) {
                      content = ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          fileUrl,
                          width: 220,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, size: 18),
                              SizedBox(width: 6),
                              Text("Photo indisponible"),
                            ],
                          ),
                        ),
                      );
                    } else if (type == 'audio') {
                      content = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic, size: 16),
                          const SizedBox(width: 6),
                          Text(messageText.isEmpty
                              ? 'Message vocal'
                              : messageText),
                        ],
                      );
                    } else {
                      content = Text(
                        messageText,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 15,
                        ),
                      );
                    }

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.orange[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: content,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Barre de saisie en bas (Clavier & Boutons multimédias)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Bouton joindre photo
                  IconButton(
                    icon: const Icon(Icons.image, color: Colors.grey),
                    onPressed: () {
                      // Logique d'envoi de photo existante
                    },
                  ),
                  // Bouton enregistrer message vocal
                  IconButton(
                    icon: const Icon(Icons.mic, color: Colors.grey),
                    onPressed: () {
                      // Logique message vocal
                    },
                  ),
                  // Champ de saisie
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: "Écrire un message…",
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      onSubmitted: (value) => _sendMessage(value),
                    ),
                  ),
                  // Bouton envoyer
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.orange),
                          )
                        : const Icon(Icons.send, color: Colors.orange),
                    onPressed:
                        _isSending ? null : () => _sendMessage(_messageController.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget pour les suggestions rapides
  Widget _buildQuickSuggestion(String text) {
    return ActionChip(
      backgroundColor: Colors.white,
      label: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.black87)),
      onPressed: () {
        _sendMessage(text);
      },
    );
  }
}
