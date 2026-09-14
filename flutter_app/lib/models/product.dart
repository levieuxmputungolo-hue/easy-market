class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String image;
  final String sellerId;
  final String sellerName;
  final double rating;
  final int stock;
  final int salesCount;
  int qty;

  Product({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.category = '',
    this.image = '',
    this.sellerId = '',
    this.sellerName = '',
    this.rating = 0,
    this.stock = 0,
    this.salesCount = 0,
    this.qty = 1,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['_id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      category: json['category'] ?? '',
      image: json['image'] ?? '',
      sellerId: json['seller_id']?.toString() ?? '',
      sellerName: json['seller_name'] ?? '',
      rating: (json['rating'] ?? 0).toDouble(),
      stock: json['stock'] ?? 0,
      salesCount: json['salesCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'description': description,
    'price': price,
    'category': category,
    'image': image,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'rating': rating,
    'stock': stock,
    'salesCount': salesCount,
  };
}
