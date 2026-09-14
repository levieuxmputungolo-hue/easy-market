import 'package:flutter/material.dart';
import '../models/product.dart';
import '../widgets/alibaba_supplier_header.dart';

class DetailScreen extends StatelessWidget {
  final Product product;
  const DetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Détail produit', style: TextStyle(color: Colors.black87, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Color(0xFFFF6A00)), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Image Gallery
            Container(
              height: 300,
              color: Colors.white,
              child: product.image.startsWith('http') || product.image.startsWith('data:')
                  ? Image.network(product.image, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Center(child: Text(product.image, style: const TextStyle(fontSize: 100))))
                  : Center(child: Text(product.image.isNotEmpty ? product.image : '📦', style: const TextStyle(fontSize: 100))),
            ),
            const SizedBox(height: 12),

            // Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('\$${product.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFFFF0033))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Color(0xFFFF6A00), size: 16),
                      Text(' ${product.rating}', style: const TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(width: 16),
                      const Icon(Icons.inventory, color: Colors.grey, size: 16),
                      Text(' Stock: ${product.stock > 0 ? product.stock : "✓"}', style: const TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(product.description, style: TextStyle(color: Colors.grey.shade700, height: 1.6)),
                  ],
                  const SizedBox(height: 16),

                  // Alibaba Supplier Header
                  AlibabaSupplierHeader(
                    sellerName: product.sellerName,
                    location: 'Gombe, Kinshasa',
                    orders: 9,
                    onCall: () {},
                    onPdf: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))]),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6A00),
                  side: const BorderSide(color: Color(0xFFFF6A00)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Ajouter au panier', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6A00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Acheter', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
