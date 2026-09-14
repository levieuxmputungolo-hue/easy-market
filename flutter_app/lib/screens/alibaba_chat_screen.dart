import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AlibabaChatScreen extends StatefulWidget {
  final String chatId;
  final String sellerName;
  final String sellerId;
  final String productName;
  final String productImage;
  final double productPrice;
  final bool isVerified;

  const AlibabaChatScreen({
    Key? key,
    this.chatId = '',
    this.sellerName = 'Vendeur',
    this.sellerId = '',
    this.productName = '',
    this.productImage = '',
    this.productPrice = 0,
    this.isVerified = true,
  }) : super(key: key);

  @override
  State<AlibabaChatScreen> createState() => _AlibabaChatScreenState();
}

class _AlibabaChatScreenState extends State<AlibabaChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _showQuickReplies = true;
  User? get _user => FirebaseAuth.instance.currentUser;

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _sendMsg(String text) {
    if (text.trim().isEmpty || _user == null) return;
    final msgText = text.trim();
    _inputCtrl.clear();
    setState(() => _showQuickReplies = false);

    // Save to Firestore
    _saveToFirestore(msgText);

    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _saveToFirestore(String text) async {
    if (_user == null || widget.chatId.isEmpty) return;
    try {
      // Add message
      await FirebaseFirestore.instance
          .collection('chats').doc(widget.chatId).collection('messages')
          .add({
        'text': text,
        'senderId': _user!.uid,
        'senderName': _user!.displayName ?? _user!.email ?? 'Acheteur',
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Update parent chat
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Send msg error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProductCard(),
            Expanded(child: _buildMessages()),
            _buildQuickReplies(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFFF6A00).withOpacity(0.1),
            child: Text(
              widget.sellerName.isNotEmpty ? widget.sellerName[0].toUpperCase() : 'V',
              style: const TextStyle(color: Color(0xFFFF6A00), fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.sellerName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, color: Colors.green.shade600, size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF52C41A), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('En ligne', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(width: 8),
                    Text('Rep. < 2 min', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(icon: Icon(Icons.phone_outlined, color: Colors.grey.shade700, size: 22), onPressed: () {}),
          IconButton(icon: Icon(Icons.more_vert, color: Colors.grey.shade700, size: 22), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildProductCard() {
    if (widget.productName.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: widget.productImage.startsWith('http')
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(widget.productImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag, color: Colors.grey, size: 24)),
                    )
                  : const Center(child: Icon(Icons.shopping_bag, color: Colors.grey, size: 24)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '\$${widget.productPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFFF0033)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6A00),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('Commander', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (widget.chatId.isEmpty) {
      return const Center(child: Text('Erreur: pas de chat', style: TextStyle(color: Colors.grey)));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats').doc(widget.chatId).collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6A00)));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                Text('Envoyez un message a ${widget.sellerName}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          );
        }
        final docs = snap.data!.docs;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final isMe = data['senderId'] == _user?.uid;
            final text = data['text'] ?? '';
            final ts = data['timestamp'] as Timestamp?;
            final time = ts != null ? _formatTime(ts.toDate()) : '';
            return _buildMessageBubble(text, isMe, time);
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(String text, bool isMe, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFFF6A00).withOpacity(0.1),
              child: Text(
                widget.sellerName.isNotEmpty ? widget.sellerName[0].toUpperCase() : 'V',
                style: const TextStyle(color: Color(0xFFFF6A00), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFFF6A00) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white.withOpacity(0.6) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 6),
          if (isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF1677FF).withOpacity(0.1),
              child: const Icon(Icons.person, size: 16, color: Color(0xFF1677FF)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickReplies() {
    if (!_showQuickReplies) return const SizedBox.shrink();
    final suggestions = [
      'Bonjour, est-ce disponible ?',
      'Quel est le prix ?',
      'Livraison possible ?',
      'Pouvez-vous faire un rabais ?',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: suggestions.map((s) => GestureDetector(
          onTap: () {
            _sendMsg(s);
            setState(() => _showQuickReplies = false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF6A00).withOpacity(0.3)),
            ),
            child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFFFF6A00))),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.mic_none, color: Colors.grey.shade600, size: 24),
              onPressed: () {},
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 38, maxHeight: 100),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ecrivez un message...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (v) => _sendMsg(v),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: Colors.grey.shade600, size: 24),
              onPressed: () {},
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _sendMsg(_inputCtrl.text),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6A00),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
