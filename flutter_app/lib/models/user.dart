class User {
  final String id;
  final String email;
  final String name;
  final String phone;

  User({required this.id, required this.email, required this.name, this.phone = ''});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id']?.toString() ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}
