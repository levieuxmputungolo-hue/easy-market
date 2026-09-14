import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product.dart';
import '../widgets/product_card.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({String? search}) async {
    setState(() => _loading = true);
    try {
      _products = await ApiService.getProducts(search: search);
      _categories = await ApiService.getCategories();
    } catch (e) {
      // Fallback local
      _products = _localProducts();
      _categories = _localCategories();
    }
    setState(() => _loading = false);
  }

  List<Product> _localProducts() {
    return [
      Product(id: '1', name: 'iPhone 15 Pro Max 256Go', price: 1499.99, image: '📱', category: 'Smartphones', rating: 4.8, sellerName: 'TechStore Pro'),
      Product(id: '2', name: 'Samsung Galaxy S24 Ultra', price: 1349.99, image: '📱', category: 'Smartphones', rating: 4.7, sellerName: 'TechStore Pro'),
      Product(id: '3', name: 'MacBook Air M3 15"', price: 1599.99, image: '💻', category: 'Ordinateurs', rating: 4.9, sellerName: 'TechStore Pro'),
      Product(id: '4', name: 'Casque Sony WH-1000XM5', price: 349.99, image: '🎧', category: 'Audio', rating: 4.6, sellerName: 'FashionHub'),
      Product(id: '5', name: 'Apple Watch Ultra 2', price: 899.99, image: '⌚', category: 'Accessoires', rating: 4.7, sellerName: 'TechStore Pro'),
      Product(id: '6', name: 'iPad Pro M4 12.9"', price: 1299.99, image: '📟', category: 'Ordinateurs', rating: 4.8, sellerName: 'TechStore Pro'),
      Product(id: '7', name: 'Robot Roomba j9+', price: 799.99, image: '🤖', category: 'Maison', rating: 4.5, sellerName: 'Maison & Deco'),
      Product(id: '8', name: 'JBL Charge 5 Bluetooth', price: 179.99, image: '🔊', category: 'Audio', rating: 4.4, sellerName: 'FashionHub'),
      Product(id: '9', name: 'Nike Air Max 270', price: 189.99, image: '👟', category: 'Mode', rating: 4.3, sellerName: 'FashionHub'),
      Product(id: '10', name: 'Sac Eastpak Provider 40L', price: 79.99, image: '🎒', category: 'Mode', rating: 4.2, sellerName: 'FashionHub'),
    ];
  }

  List<Map<String, dynamic>> _localCategories() {
    return [
      {'name': 'Smartphones'}, {'name': 'Ordinateurs'}, {'name': 'Audio'},
      {'name': 'Accessoires'}, {'name': 'Maison'}, {'name': 'Mode'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // Header orange Alibaba style
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16, bottom: 36),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF6A00), Color(0xFFFF8C00)]),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('AISY Market', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.chat_bubble_outline, color: Colors.white), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () {}),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un produit...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFF6A00)),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); _loadData(); }),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (v) => _loadData(search: v.isEmpty ? null : v),
                  ),
                ),
              ],
            ),
          ),

          // Categories horizontal scroll
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            transform: Matrix4.translationValues(0, -28, 0),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))]),
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _categories.length + 1,
              itemBuilder: (ctx, i) {
                final icons = ['🏪', '📱', '💻', '🎧', '⌚', '🏠', '👕'];
                final name = i == 0 ? 'Tous' : _categories[i - 1]['name'];
                return GestureDetector(
                  onTap: () { _searchCtrl.text = name == 'Tous' ? '' : name; _loadData(search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(icons[i % icons.length], style: const TextStyle(fontSize: 20))),
                        ),
                        const SizedBox(height: 4),
                        Text(name, style: const TextStyle(fontSize: 10, color: Colors.black87)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Section title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🔥 Produits populaires', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                TextButton(onPressed: () => _searchCtrl.text.isNotEmpty ? _loadData() : null, child: const Text('Voir tout', style: TextStyle(color: Color(0xFFFF6A00), fontSize: 13))),
              ],
            ),
          ),

          // Products grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6A00)))
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _products.length,
                    itemBuilder: (ctx, i) => ProductCard(
                      product: _products[i],
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(product: _products[i]))),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
