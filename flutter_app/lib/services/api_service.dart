import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/user.dart';

class ApiService {
  static const String baseUrl = 'https://easy-market-fqz8.onrender.com/api';

  static Future<List<Product>> getProducts({String? search}) async {
    final uri = Uri.parse('$baseUrl/products').replace(queryParameters: search != null ? {'search': search} : null);
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['products'] as List).map((e) => Product.fromJson(e)).toList();
    }
    throw Exception('Erreur chargement produits');
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final res = await http.get(Uri.parse('$baseUrl/categories'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  static Future<User> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/users/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode == 200) {
      return User.fromJson(jsonDecode(res.body));
    }
    throw Exception('Email ou mot de passe incorrect');
  }

  static Future<User> register(String name, String email, String phone, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/users/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'phone': phone, 'password': password}),
    );
    if (res.statusCode == 200) {
      return User.fromJson(jsonDecode(res.body));
    }
    throw Exception('Erreur inscription');
  }

  static Future<void> placeOrder(String userId, List<Product> items, double total) async {
    await http.post(
      Uri.parse('$baseUrl/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'items': items.map((e) => e.toJson()).toList(),
        'total': total,
      }),
    );
  }

  static Future<List<Map<String, dynamic>>> getOrders(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/orders/$userId'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  static Future<Map<String, dynamic>> getPaymentOperators() async {
    final res = await http.get(Uri.parse('$baseUrl/payments/operators'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {'operators': []};
  }

  static Future<Map<String, dynamic>> initPayment({
    required String orderId,
    required double amount,
    required String phone,
    required String operator,
    required String userId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/mobile/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'order_id': orderId,
        'amount': amount,
        'phone': phone,
        'operator': operator,
        'user_id': userId,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Erreur paiement');
  }

  static Future<Map<String, dynamic>> confirmPayment({
    required String code,
    required String orderId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payments/mobile/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'order_id': orderId,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Erreur confirmation paiement');
  }
}
