import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'screens/alibaba_chat_screen.dart';
import 'services/api_service.dart';

// FCM background handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Demander la permission
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  debugPrint('FCM permission: ${settings.authorizationStatus}');

  // Obtenir le token
  final token = await messaging.getToken();
  debugPrint('FCM token: $token');
  if (token != null) {
    await _saveFCMToken(token);
  }

  // Token refresh
  messaging.onTokenRefresh.listen(_saveFCMToken);

  // Foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');
    _showLocalNotification(message);
  });

  // Background message tap
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('Message opened app: ${message.notification?.title}');
  });

  // Notifications init
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await _localNotifs.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
}

Future<void> _saveFCMToken(String token) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance.collection('fcm_tokens').doc(token).set({
      'userId': user.uid,
      'token': token,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Error saving FCM token: $e');
  }
}

void _showLocalNotification(RemoteMessage message) async {
  const androidDetails = AndroidNotificationDetails(
    'easymarket_channel',
    'Easy Market Notifications',
    importance: Importance.high,
    priority: Priority.high,
  );
  const details = NotificationDetails(android: androidDetails, iOS: const DarwinNotificationDetails());
  await _localNotifs.show(
    message.hashCode,
    message.notification?.title ?? 'Easy Market',
    message.notification?.body ?? '',
    details,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _initFCM();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const EasyMarketApp());
}

class EasyMarketApp extends StatelessWidget {
  const EasyMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Market',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1677FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1677FF),
          primary: const Color(0xFF1677FF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const AuthGate(),
    );
  }
}

// ─── AUTH GATE ───
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// ─── LOGIN SCREEN ───
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _loginEmail() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await _syncVendeurToFirestore();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Erreur de connexion')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loginGoogle() async {
    setState(() => _loading = true);
    try {
      final googleUser = await GoogleSignIn(
        scopes: ['email'],
      ).signIn();
      if (googleUser == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connexion Google annulee')),
        );
        setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur: tokens Google non obtenus. Verifiez la configuration Firebase.')),
        );
        setState(() => _loading = false);
        return;
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _syncVendeurToFirestore();
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Firebase: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Google: $e')),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loginApple() async {
    setState(() => _loading = true);
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      if (appleCredential.identityToken == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur: token Apple non obtenu')),
        );
        setState(() => _loading = false);
        return;
      }
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      await _syncVendeurToFirestore();
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Firebase: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Apple: $e')),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncVendeurToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('vendeurs').doc(user.uid).get();
      if (!doc.exists) {
        final now = DateTime.now();
        await FirebaseFirestore.instance.collection('vendeurs').doc(user.uid).set({
          'uid': user.uid,
          'name': user.displayName ?? 'Vendeur',
          'email': user.email ?? '',
          'plan': 'commission',
          'commission_rate': 8,
          'trial_active': true,
          'trial_start': now.toIso8601String(),
          'trial_end': now.add(const Duration(days: 90)).toIso8601String(),
          'subscription_status': 'trial',
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Vendeur sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(Icons.shopping_bag_outlined, size: 64, color: Color(0xFF1677FF)),
              const SizedBox(height: 12),
              const Text('Easy Market', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1677FF))),
              const SizedBox(height: 4),
              const Text('Achetez et vendez en toute simplicite',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 40),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _loginEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1677FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Se connecter', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
              const Row(children: [
                Expanded(child: Divider(color: Colors.grey)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou', style: TextStyle(color: Colors.grey))),
                Expanded(child: Divider(color: Colors.grey)),
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _socialButton(
                      'Google',
                      const Color(0xFF4285F4),
                      Icons.g_mobiledata,
                      _loginGoogle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _socialButton(
                      'Apple',
                      Colors.black,
                      Icons.apple,
                      _loginApple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pas encore de compte ? ', style: TextStyle(color: Colors.grey)),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('Creer un compte', style: TextStyle(color: Color(0xFF1677FF), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialButton(String label, Color color, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : onTap,
        icon: Icon(icon, color: color, size: 22),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity( 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ─── REGISTER SCREEN ───
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplissez au moins le nom, email et mot de passe')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());
      // Save user profile to Firestore
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': 'acheteur',
        'created_at': FieldValue.serverTimestamp(),
      });
      // Auto-create vendeur doc with 3-month trial
      final now = DateTime.now();
      await FirebaseFirestore.instance.collection('vendeurs').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'plan': 'commission',
        'commission_rate': 8,
        'trial_active': true,
        'trial_start': now.toIso8601String(),
        'trial_end': now.add(const Duration(days: 90)).toIso8601String(),
        'subscription_status': 'trial',
        'created_at': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Erreur d\'inscription')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Creer un compte'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            _input(_nameCtrl, 'Nom complet *', Icons.person_outlined),
            const SizedBox(height: 12),
            _input(_emailCtrl, 'Email *', Icons.email_outlined, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _input(_phoneCtrl, 'Telephone', Icons.phone_outlined, keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: 'Mot de passe *',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1677FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Creer mon compte', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Deja un compte ? ', style: TextStyle(color: Colors.grey)),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text('Se connecter', style: TextStyle(color: Color(0xFF1677FF), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ─── MAIN SCREEN ───
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeTab(),
          MessagesTab(),
          PublishTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1677FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'Publier'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}

// ─── HOME TAB (Firestore + Local Products + Member Stats) ───
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  int _memberCount = 3;
  int _vendorCount = 1;
  int _unreadNotifs = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadMemberStats();
    _loadUnreadNotifs();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    List<Map<String, dynamic>> all = [];

    // 1. Load from Firestore
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('statut', isEqualTo: 'publié')
          .get();
      for (final doc in snap.docs) {
        all.add({'_id': doc.id, ...doc.data()});
      }
    } catch (e) {
      debugPrint('Firestore error: $e');
    }

    // 2. Merge local products ONLY if not already in Firestore (by title)
    final prefs = await SharedPreferences.getInstance();
    final localJson = prefs.getString('local_products') ?? '[]';
    final localProds = (json.decode(localJson) as List).cast<Map<String, dynamic>>();
    List<String> toRemove = [];
    for (final p in localProds) {
      final pid = p['_id'] ?? '';
      final pName = (p['titre'] ?? p['name'] ?? '').toString().toLowerCase().trim();
      final isDuplicate = all.any((x) =>
        x['_id'] == pid ||
        (x['titre'] ?? x['name'] ?? '').toString().toLowerCase().trim() == pName
      );
      if (isDuplicate) {
        toRemove.add(pid);
      } else {
        all.add(p);
      }
    }
    // Clean up local duplicates
    if (toRemove.isNotEmpty) {
      final cleaned = localProds.where((p) => !toRemove.contains(p['_id'])).toList();
      await prefs.setString('local_products', json.encode(cleaned));
    }

    setState(() {
      _products = all;
      _loading = false;
    });
  }

  Future<void> _loadMemberStats() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('stats').doc('counts').get();
      if (doc.exists) {
        final d = doc.data()!;
        setState(() {
          _memberCount = (d['users'] ?? 3) as int;
          _vendorCount = (d['vendors'] ?? 1) as int;
        });
      }
    } catch (e) {}
  }

  Future<void> _loadUnreadNotifs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(user.uid)
          .collection('items')
          .where('read', isEqualTo: false)
          .get();
      if (mounted) setState(() => _unreadNotifs = snap.docs.length);
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadProducts();
          await _loadMemberStats();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF1677FF), size: 20),
                    const SizedBox(width: 4),
                    const Text('Kinshasa, RDC', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 12),
                            Icon(Icons.search, color: Colors.grey, size: 18),
                            SizedBox(width: 8),
                            Text('Rechercher...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications_outlined, size: 22),
                          if (_unreadNotifs > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _unreadNotifs > 9 ? '9+' : '$_unreadNotifs',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _statCard(Icons.people_outline, '$_memberCount', 'membres'),
                    const SizedBox(width: 8),
                    _statCard(Icons.storefront_outlined, '$_vendorCount', 'vendeurs'),
                    const SizedBox(width: 8),
                    _statCard(Icons.inventory_2_outlined, '${_products.length}', 'produits'),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF1677FF))),
              )
            else if (_products.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 60, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Aucun produit', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Publiez votre premier produit !', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _productCard(_products[i]),
                    childCount: _products.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0F0F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF1677FF)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2A7DE1))),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final img = (p['images'] as List?)?.isNotEmpty == true
        ? p['images'][0]
        : (p['image'] ?? '');
    final titre = p['titre'] ?? p['name'] ?? 'Produit';
    final price = p['price'] ?? 0;
    final seller = p['seller_name'] ?? 'Vendeur';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: p))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity( 0.05), blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: img.toString().startsWith('http')
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: Image.network(img, fit: BoxFit.cover),
                      )
                    : const Center(child: Icon(Icons.shopping_bag, color: Colors.grey, size: 40)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\$${price.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1677FF))),
                  const SizedBox(height: 2),
                  Text(titre,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(seller, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PRODUCT DETAIL (Alibaba Style Gallery) ───
class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailPage({super.key, required this.product});
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int _currentIdx = 0;
  bool _autoplay = true;
  Timer? _autoTimer;
  double _progress = 0;
  Timer? _progressTimer;
  bool _isFavorite = false;
  int _selectedTab = 0;
  final PageController _imgController = PageController();

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _progressTimer?.cancel();
    _imgController.dispose();
    super.dispose();
  }

  void _startAutoplay() {
    _autoTimer?.cancel();
    _progressTimer?.cancel();
    _progress = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      setState(() {
        _progress += 0.0125;
        if (_progress >= 1.0) {
          _progress = 0;
          _nextImage();
        }
      });
    });
  }

  void _stopAutoplay() {
    _autoTimer?.cancel();
    _progressTimer?.cancel();
  }

  void _nextImage() {
    final imgs = _getImages();
    if (imgs.length <= 1) return;
    setState(() => _currentIdx = (_currentIdx + 1) % imgs.length);
    if (_imgController.hasClients) {
      _imgController.animateToPage(_currentIdx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _prevImage() {
    final imgs = _getImages();
    if (imgs.length <= 1) return;
    setState(() => _currentIdx = (_currentIdx - 1 + imgs.length) % imgs.length);
    if (_imgController.hasClients) {
      _imgController.animateToPage(_currentIdx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _goToImage(int idx) {
    final imgs = _getImages();
    if (idx < 0 || idx >= imgs.length) return;
    setState(() { _currentIdx = idx; _progress = 0; });
    if (_imgController.hasClients) {
      _imgController.animateToPage(idx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _toggleAutoplay() {
    setState(() => _autoplay = !_autoplay);
    _autoplay ? _startAutoplay() : _stopAutoplay();
  }

  List<String> _getImages() {
    final imgs = <String>[];
    final raw = widget.product['images'];
    if (raw is List) {
      for (final img in raw) {
        if (img is String && (img.startsWith('http') || img.startsWith('data:'))) imgs.add(img);
      }
    }
    if (imgs.isEmpty) {
      final single = widget.product['image'];
      if (single is String && (single.startsWith('http') || single.startsWith('data:'))) imgs.add(single);
    }
    return imgs;
  }

  Widget _buildImg(String img, BoxFit fit) {
    if (img.startsWith('http')) {
      return Image.network(img, fit: fit, width: double.infinity,
        loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Color(0xFFFF6F00), strokeWidth: 2)),
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 60, color: Colors.grey)));
    }
    try {
      final b64 = img.contains(',') ? img.split(',').last : img;
      return Image.memory(base64Decode(b64), fit: fit, width: double.infinity, gaplessPlayback: true);
    } catch (_) {
      return const Center(child: Icon(Icons.image, size: 60, color: Colors.grey));
    }
  }

  String _getChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> _openChat() async {
    final p = widget.product;
    final imgs = _getImages();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour contacter le vendeur')));
      return;
    }
    final seller = p['seller_name'] ?? 'Vendeur';
    final sellerId = p['seller_id'] ?? '';
    final titre = p['titre'] ?? p['name'] ?? '';
    final price = (p['price'] ?? 0).toDouble();
    if (sellerId == user.uid && sellerId.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("C'est votre propre produit !")));
      return;
    }
    final chatId = _getChatId(user.uid, sellerId.isNotEmpty ? sellerId : 'seller_unknown');
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();
    if (!chatDoc.exists) {
      await chatRef.set({
        'participants': [user.uid, sellerId.isNotEmpty ? sellerId : 'unknown'],
        'seller_id': sellerId.isNotEmpty ? sellerId : 'unknown',
        'seller_name': seller, 'buyer_name': user.displayName ?? user.email ?? 'Acheteur',
        'buyer_id': user.uid, 'product_name': titre,
        'product_image': imgs.isNotEmpty ? imgs[0] : '', 'product_price': price,
        'lastMessage': '', 'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AlibabaChatScreen(
        chatId: chatId, sellerName: seller, sellerId: sellerId.isNotEmpty ? sellerId : 'unknown',
        productName: titre, productImage: imgs.isNotEmpty ? imgs[0] : '', productPrice: price,
      )));
    }
  }

  Future<void> _addToCart(Map<String, dynamic> p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour ajouter au panier')));
      return;
    }
    try {
      final cartRef = FirebaseFirestore.instance.collection('carts').doc(user.uid);
      final cartDoc = await cartRef.get();
      final items = cartDoc.exists ? List<Map<String, dynamic>>.from(cartDoc.data()!['items'] ?? []) : [];
      final productId = p['_id'] ?? '';
      final existingIdx = items.indexWhere((x) => x['product_id'] == productId);
      if (existingIdx >= 0) {
        items[existingIdx]['qty'] = (items[existingIdx]['qty'] ?? 1) + 1;
      } else {
        items.add({
          'product_id': productId, 'titre': p['titre'] ?? p['name'] ?? '',
          'price': p['price'] ?? 0, 'image': (p['images'] as List?)?.isNotEmpty == true ? p['images'][0] : (p['image'] ?? ''),
          'seller_name': p['seller_name'] ?? 'Vendeur', 'seller_id': p['seller_id'] ?? '', 'qty': 1,
        });
      }
      await cartRef.set({'user_id': user.uid, 'items': items, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté au panier !'), backgroundColor: Color(0xFFFF6F00)));
    } catch (e) { debugPrint('Add to cart error: $e'); }
  }

  Future<void> _buyNow(Map<String, dynamic> p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous pour acheter')));
      return;
    }
    final price = (p['price'] ?? 0).toDouble();
    final productId = p['_id'] ?? '';
    final sellerId = p['seller_id'] ?? '';
    final sellerName = p['seller_name'] ?? 'Vendeur';
    final productName = p['titre'] ?? p['name'] ?? '';
    if (!mounted) return;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(productName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('\$${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFF6F00))),
          const SizedBox(height: 4),
          Text('Vendeur: $sellerName', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          const Text('Mode de paiement', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _paymentOption(Icons.phone_android, 'M-Pesa', 'Paiement mobile', () => _confirmOrder(user.uid, productId, price, sellerId, sellerName, 'mpesa', ctx)),
          const SizedBox(height: 8),
          _paymentOption(Icons.phone_android, 'Orange Money', 'Paiement mobile', () => _confirmOrder(user.uid, productId, price, sellerId, sellerName, 'orange_money', ctx)),
          const SizedBox(height: 8),
          _paymentOption(Icons.phone_android, 'Airtel Money', 'Paiement mobile', () => _confirmOrder(user.uid, productId, price, sellerId, sellerName, 'airtel_money', ctx)),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _paymentOption(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFFF6F00).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: const Color(0xFFFF6F00), size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Future<void> _confirmOrder(String userId, String productId, double price, String sellerId, String sellerName, String method, BuildContext ctx) async {
    Navigator.pop(ctx);
    try {
      final phoneController = TextEditingController();
      final phone = await showDialog<String>(
        context: ctx,
        builder: (ctx2) => AlertDialog(
          title: Text('Numero $method'),
          content: TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(hintText: 'Ex: +243...'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2), child: Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx2, phoneController.text), child: Text('Payer')),
          ],
        ),
      );
      if (phone == null || phone.isEmpty) return;

      final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
      final result = await ApiService.initPayment(
        orderId: orderId,
        amount: price,
        phone: phone,
        operator: method,
        userId: userId,
      );

      if (result['success'] == true) {
        await FirebaseFirestore.instance.collection('orders').add({
          'order_id': orderId, 'user_id': userId, 'product_id': productId, 'price': price,
          'seller_id': sellerId, 'seller_name': sellerName, 'payment_method': method,
          'status': 'paye', 'created_at': FieldValue.serverTimestamp(),
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paiement effectue via $method !'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur paiement: ${result['message'] ?? 'Inconnu'}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint('Order error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final imgs = _getImages();
    final totalSlides = imgs.length;
    final titre = p['titre'] ?? p['name'] ?? 'Produit';
    final price = (p['price'] ?? 0).toDouble();
    final desc = p['description'] ?? '';
    final seller = p['seller_name'] ?? 'Vendeur';
    final stock = p['stock'];
    final rating = (p['rating'] ?? 4.8).toDouble();
    final reviews = p['reviews'] ?? 238;
    final hasVideo = p['video_url'] != null && (p['video_url'] as String).isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          // ─── HEADER ───
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
                  Expanded(child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.share_outlined, size: 20), onPressed: () {}),
                  IconButton(
                    icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, size: 20, color: _isFavorite ? Colors.red : null),
                    onPressed: () => setState(() => _isFavorite = !_isFavorite),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ═══════════════════════════════════════════════
                // 1. GALERIE D'IMAGES PREMIUM
                // ═══════════════════════════════════════════════
                Container(
                  color: Colors.white,
                  child: Column(children: [
                    SizedBox(
                      width: double.infinity,
                      height: 420,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _imgController,
                            itemCount: totalSlides > 0 ? totalSlides : 1,
                            onPageChanged: (i) => setState(() { _currentIdx = i; _progress = 0; }),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => _showZoomedImages(context, imgs, i),
                              child: SizedBox.expand(
                                child: totalSlides > 0
                                    ? _buildImg(imgs[i], BoxFit.cover)
                                    : const Center(child: Icon(Icons.shopping_bag, color: Colors.grey, size: 80)),
                              ),
                            ),
                          ),
                          // Badge photos
                          if (totalSlides > 1)
                            Positioned(
                              top: 12, left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(12)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text('$totalSlides Photos', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          // Badge vidéo
                          if (hasVideo)
                            Positioned(
                              top: 12, right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: const Color(0xFFFF6F00), borderRadius: BorderRadius.circular(12)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.videocam, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Vidéo', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          // Counter
                          if (totalSlides > 1)
                            Positioned(
                              bottom: 50, right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(12)),
                                child: Text('${_currentIdx + 1} / $totalSlides',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          // Autoplay toggle
                          if (totalSlides > 1)
                            Positioned(
                              bottom: 50, left: 12,
                              child: GestureDetector(
                                onTap: _toggleAutoplay,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _autoplay ? const Color(0xFF00C853).withOpacity(0.85) : Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(_autoplay ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 14),
                                    const SizedBox(width: 3),
                                    Text(_autoplay ? 'Autoplay: ON' : 'Autoplay: OFF',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              ),
                            ),
                          // Prev/Next arrows
                          if (totalSlides > 1) ...[
                            Positioned(left: 8, top: 0, bottom: 0, child: Center(
                              child: GestureDetector(
                                onTap: () { _stopAutoplay(); _prevImage(); if (_autoplay) _startAutoplay(); },
                                child: Container(width: 36, height: 36,
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), shape: BoxShape.circle),
                                  child: const Icon(Icons.chevron_left, color: Colors.white, size: 24)),
                              ),
                            )),
                            Positioned(right: 8, top: 0, bottom: 0, child: Center(
                              child: GestureDetector(
                                onTap: () { _stopAutoplay(); _nextImage(); if (_autoplay) _startAutoplay(); },
                                child: Container(width: 36, height: 36,
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), shape: BoxShape.circle),
                                  child: const Icon(Icons.chevron_right, color: Colors.white, size: 24)),
                              ),
                            )),
                          ],
                          // Gradient
                          Positioned(bottom: 0, left: 0, right: 0, child: Container(
                            height: 40,
                            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.white])),
                          )),
                        ],
                      ),
                    ),
                    // Progress bar
                    if (totalSlides > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(children: List.generate(totalSlides, (i) {
                          final isActive = i == _currentIdx;
                          final isPast = i < _currentIdx;
                          return Expanded(
                            child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
                                  color: isPast ? const Color(0xFFFF6F00) : isActive ? const Color(0xFFE0E0E0) : const Color(0xFFF0F0F0)),
                              child: isActive ? FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: _progress,
                                  child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0xFFFF6F00)))) : null,
                            ),
                          );
                        })),
                      ),
                    // Thumbnails
                    if (totalSlides > 1)
                      SizedBox(
                        height: 60,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: totalSlides, separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) => GestureDetector(
                            onTap: () { _stopAutoplay(); _goToImage(i); if (_autoplay) _startAutoplay(); },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200), width: 56, height: 56,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: i == _currentIdx ? const Color(0xFFFF6F00) : const Color(0xFFE0E0E0), width: i == _currentIdx ? 2 : 1)),
                              child: ClipRRect(borderRadius: BorderRadius.circular(7), child: _buildImg(imgs[i], BoxFit.cover)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 2. PRIX PROFESSIONNEL
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      ...List.generate(5, (i) => Icon(Icons.star, size: 16, color: i < rating.round() ? Colors.amber : Colors.grey.shade300)),
                      const SizedBox(width: 6),
                      Text('$rating', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Text('($reviews avis)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('US ', style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                      Text('${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFFFF6F00))),
                    ]),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFFF6F00).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: const Text('Prix négociable', style: TextStyle(fontSize: 12, color: Color(0xFFFF6F00), fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      _infoTag(Icons.check_circle, stock != null && stock > 0 ? 'En stock : $stock' : 'Disponible', Colors.green),
                      const SizedBox(width: 12),
                      _infoTag(Icons.local_shipping_outlined, 'Livraison', Colors.blue),
                      const SizedBox(width: 12),
                      _infoTag(Icons.verified_outlined, 'Garantie', Colors.purple),
                    ]),
                  ]),
                ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 3. INFORMATIONS RAPIDES
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Spécifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _specRow('🚗', 'Marque', p['marque'] ?? 'Toyota'),
                    _specRow('📅', 'Année', p['annee'] ?? '2024'),
                    _specRow('⚙️', 'Transmission', p['transmission'] ?? 'Automatique'),
                    _specRow('⛽', 'Carburant', p['carburant'] ?? 'Essence'),
                    _specRow('📍', 'Localisation', p['localisation'] ?? 'Kinshasa'),
                    _specRow('🎨', 'Couleur', p['couleur'] ?? 'Noir'),
                    _specRow('📄', 'Documents', p['documents'] ?? 'Plaque'),
                  ]),
                ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 4. BLOC VENDEUR PREMIUM
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFFF6F00),
                        child: Text(seller.isNotEmpty ? seller[0].toUpperCase() : 'S',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(seller, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Row(children: [
                          ...List.generate(5, (i) => Icon(Icons.star, size: 14, color: i < 5 ? Colors.amber : Colors.grey.shade300)),
                          const SizedBox(width: 4),
                          Text('$rating', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    _sellerBadge(Icons.verified, 'Verified Supplier', const Color(0xFF00C853)),
                    const SizedBox(height: 6),
                    _sellerBadge(Icons.timer_outlined, 'Répond en moins de 5 min', Colors.blue),
                    const SizedBox(height: 6),
                    _sellerBadge(Icons.calendar_today, '3 ans sur EasyMarket', Colors.orange),
                    const SizedBox(height: 6),
                    _sellerBadge(Icons.shopping_cart_outlined, '150 ventes réalisées', Colors.purple),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            final sellerId = p['seller_id'] ?? '';
                            if (sellerId == user.uid) return;
                          }
                          _openChat();
                        },
                        icon: const Icon(Icons.store_outlined, size: 18),
                        label: const Text('Voir le magasin'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6F00),
                          side: const BorderSide(color: Color(0xFFFF6F00)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton.icon(
                        onPressed: _openChat,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Contacter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6F00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        ),
                      )),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _sellerStat('3 min', 'Temps de\nréponse'),
                        _sellerStat('98%', 'Réponses'),
                        _sellerStat('150', 'Ventes'),
                        _sellerStat('2022', 'Depuis'),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 6. ONGLETS
                // ═══════════════════════════════════════════════
                Container(
                  color: Colors.white,
                  child: Column(children: [
                    Row(children: ['Description', 'Caractéristiques', 'Avis'].asMap().entries.map((e) {
                      final idx = e.key;
                      final label = e.value;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = idx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(border: Border(
                              bottom: BorderSide(color: _selectedTab == idx ? const Color(0xFFFF6F00) : Colors.transparent, width: 2),
                            )),
                            child: Center(child: Text(label,
                              style: TextStyle(fontSize: 13, fontWeight: _selectedTab == idx ? FontWeight.w700 : FontWeight.w500,
                                  color: _selectedTab == idx ? const Color(0xFFFF6F00) : Colors.grey))),
                          ),
                        ),
                      );
                    }).toList()),
                  ]),
                ),
                // Tab content
                if (_selectedTab == 0)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                    child: desc.isNotEmpty ? Text(desc, style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87))
                        : const Text('Aucune description disponible', style: TextStyle(color: Colors.grey)),
                  ),
                if (_selectedTab == 1)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _specRow('🚗', 'Marque', p['marque'] ?? 'Toyota'),
                      _specRow('📅', 'Année', p['annee'] ?? '2024'),
                      _specRow('⚙️', 'Transmission', p['transmission'] ?? 'Automatique'),
                      _specRow('⛽', 'Carburant', p['carburant'] ?? 'Essence'),
                      _specRow('📍', 'Localisation', p['localisation'] ?? 'Kinshasa'),
                      _specRow('🎨', 'Couleur', p['couleur'] ?? 'Noir'),
                    ]),
                  ),
                if (_selectedTab == 2)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('$rating', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ...List.generate(5, (i) => Row(children: [
                            SizedBox(width: 80, child: Text('${5 - i}★', style: const TextStyle(fontSize: 12))),
                            Expanded(child: LinearProgressIndicator(
                              value: i == 0 ? 0.78 : i == 1 ? 0.15 : i == 2 ? 0.05 : 0.01,
                              backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6F00)),
                            )),
                          ])),
                        ]),
                      ]),
                      const SizedBox(height: 16),
                      Text('$reviews avis', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 7. PRODUITS SIMILAIRES
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Produits similaires', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 4, separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => Container(
                          width: 140,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(height: 90, width: 140, decoration: BoxDecoration(
                              color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                              child: const Center(child: Icon(Icons.directions_car, size: 40, color: Colors.grey)),
                            ),
                            Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(['Toyota Prado', 'Toyota RAV4', 'Toyota Corolla', 'Toyota Yaris'][i],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text('\$${[6800, 7300, 4500, 3200][i]}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFF6F00))),
                              Row(children: List.generate(5, (j) => Icon(Icons.star, size: 10, color: j < 4 + (i.isEven ? 1 : 0) ? Colors.amber : Colors.grey.shade300))),
                            ])),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),

                // ═══════════════════════════════════════════════
                // 9. SÉCURITÉ
                // ═══════════════════════════════════════════════
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.shield_outlined, color: Color(0xFFFF6F00), size: 20),
                      SizedBox(width: 8),
                      Text('Protection EasyMarket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 12),
                    _securityRow(Icons.lock_outline, 'Paiement sécurisé'),
                    const SizedBox(height: 8),
                    _securityRow(Icons.verified_user_outlined, 'Vendeur vérifié'),
                    const SizedBox(height: 8),
                    _securityRow(Icons.headset_mic_outlined, 'Assistance 24/7'),
                    const SizedBox(height: 8),
                    _securityRow(Icons.replay_outlined, 'Politique de remboursement'),
                  ]),
                ),
                const SizedBox(height: 80),
              ]),
            ),
          ),

          // ═══════════════════════════════════════════════
          // 5. BOUTONS FLOTTANTS EN BAS
          // ═══════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, -4)),
            ]),
            child: SafeArea(
              top: false,
              child: Row(children: [
                // Favoris
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? Colors.red : Colors.grey, size: 22),
                  const SizedBox(height: 2),
                  const Text('Favoris', style: TextStyle(fontSize: 10)),
                ]),
                const SizedBox(width: 16),
                // Chat
                GestureDetector(
                  onTap: _openChat,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.chat_bubble_outline, color: Color(0xFF1677FF), size: 22),
                    const SizedBox(height: 2),
                    const Text('Chat', style: TextStyle(fontSize: 10)),
                  ]),
                ),
                const SizedBox(width: 16),
                // Appeler
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.phone_outlined, color: Color(0xFF00C853), size: 22),
                  const SizedBox(height: 2),
                  const Text('Appeler', style: TextStyle(fontSize: 10)),
                ]),
                const SizedBox(width: 12),
                // Ajouter au panier
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _addToCart(p),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFFF6F00),
                      side: const BorderSide(color: Color(0xFFFF6F00)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                // Acheter (orange)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _buyNow(p),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6F00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('Acheter', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showZoomedImages(BuildContext context, List<String> imgs, int initial) {
    if (imgs.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _ZoomGallery(imgs: imgs, initial: initial)));
  }

  Widget _infoTag(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _specRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _sellerBadge(IconData icon, String text, Color color) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _sellerStat(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFFF6F00))),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), textAlign: TextAlign.center),
    ]);
  }

  Widget _securityRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF00C853)),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─── ZOOM GALLERY ───
class _ZoomGallery extends StatefulWidget {
  final List<String> imgs;
  final int initial;
  const _ZoomGallery({required this.imgs, this.initial = 0});
  @override
  State<_ZoomGallery> createState() => _ZoomGalleryState();
}

class _ZoomGalleryState extends State<_ZoomGallery> {
  late PageController _ctrl;
  late int _idx;

  @override
  void initState() {
    super.initState();
    _idx = widget.initial;
    _ctrl = PageController(initialPage: _idx);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _buildZoomImg(String img) {
    if (img.startsWith('http')) {
      return InteractiveViewer(
        maxScale: 4.0,
        child: Image.network(img, fit: BoxFit.contain,
          loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Color(0xFFFF6F00))),
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 60, color: Colors.grey))),
      );
    }
    try {
      final b64 = img.contains(',') ? img.split(',').last : img;
      return InteractiveViewer(maxScale: 4.0, child: Image.memory(base64Decode(b64), fit: BoxFit.contain, gaplessPlayback: true));
    } catch (_) {
      return const Center(child: Icon(Icons.image, size: 60, color: Colors.grey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _ctrl, itemCount: widget.imgs.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) => Center(child: _buildZoomImg(widget.imgs[i])),
        ),
        Positioned(top: 40, right: 16, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context),
        )),
        Positioned(bottom: 30, left: 0, right: 0, child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(16)),
            child: Text('${_idx + 1} / ${widget.imgs.length}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        )),
      ]),
    );
  }
}

// ─── PUBLISH TAB ───
class PublishTab extends StatefulWidget {
  const PublishTab({super.key});
  @override
  State<PublishTab> createState() => _PublishTabState();
}

class _PublishTabState extends State<PublishTab> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _marqueCtrl = TextEditingController();
  final _anneeCtrl = TextEditingController();
  final _localisationCtrl = TextEditingController();
  final _couleurCtrl = TextEditingController();
  final _documentsCtrl = TextEditingController();
  String _category = 'Véhicules';
  String _transmission = '';
  String _carburant = '';
  bool _prixNegociable = false;
  bool _livraison = false;
  bool _garantie = false;
  bool _publishing = false;

  final _categories = ['Véhicules', 'Mode', 'Electronique', 'Maison', 'Beaute', 'Sport', 'Alimentation', 'Autre'];

  Future<void> _publish() async {
    if (_nameCtrl.text.isEmpty || _priceCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplissez au moins le nom et le prix')),
      );
      return;
    }

    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prix invalide')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    setState(() => _publishing = true);

    final product = {
      'titre': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': price,
      'category': _category,
      'statut': 'publié',
      'seller_id': user?.uid ?? '',
      'vendeur_id': user?.uid ?? '',
      'seller_name': user?.displayName ?? user?.email ?? 'Vendeur',
      'images': <String>[],
      'rating': 0.0,
      'reviews': 0,
      'salesCount': 0,
      'marque': _marqueCtrl.text.trim(),
      'annee': _anneeCtrl.text.trim(),
      'transmission': _transmission,
      'carburant': _carburant,
      'localisation': _localisationCtrl.text.trim(),
      'couleur': _couleurCtrl.text.trim(),
      'documents': _documentsCtrl.text.trim(),
      'prix_negociable': _prixNegociable,
      'livraison': _livraison,
      'garantie': _garantie,
      'createdAt': DateTime.now().toIso8601String(),
    };

    bool savedToFirestore = false;
    try {
      final docRef = await FirebaseFirestore.instance.collection('products').add({
        ...product,
        'createdAt': FieldValue.serverTimestamp(),
      });
      product['_id'] = docRef.id;
      savedToFirestore = true;
    } catch (e) {
      debugPrint('Firestore save error: $e');
    }

    if (!savedToFirestore) {
      product['_id'] = 'local_${DateTime.now().millisecondsSinceEpoch}';
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_products') ?? '[]';
      final localProds = (json.decode(localJson) as List).cast<Map<String, dynamic>>();
      localProds.insert(0, product);
      await prefs.setString('local_products', json.encode(localProds));
    } else {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString('local_products') ?? '[]';
      final localProds = (json.decode(localJson) as List).cast<Map<String, dynamic>>();
      final cleaned = localProds.where((p) =>
        !((p['titre'] ?? '') == product['titre'] && (p['seller_id'] ?? '') == product['seller_id'])
      ).toList();
      await prefs.setString('local_products', json.encode(cleaned));
    }

    setState(() => _publishing = false);
    _nameCtrl.clear(); _priceCtrl.clear(); _descCtrl.clear();
    _marqueCtrl.clear(); _anneeCtrl.clear(); _localisationCtrl.clear();
    _couleurCtrl.clear(); _documentsCtrl.clear();
    setState(() { _transmission = ''; _carburant = ''; _prixNegociable = false; _livraison = false; _garantie = false; });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit publié avec succès !')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Publier un produit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _input(_nameCtrl, 'Nom du produit *'),
            const SizedBox(height: 12),
            _input(_priceCtrl, 'Prix (\$) *', keyboard: TextInputType.number),
            const SizedBox(height: 12),
            _input(_descCtrl, 'Description', maxLines: 3),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 16),
            const Text('Spécifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _input(_marqueCtrl, '🚗 Marque')),
              const SizedBox(width: 12),
              Expanded(child: _input(_anneeCtrl, '📅 Année', keyboard: TextInputType.number)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _transmission.isEmpty ? null : _transmission,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14), hintText: '⚙️ Transmission'),
                items: ['Automatique', 'Manuelle'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _transmission = v ?? ''),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(
                value: _carburant.isEmpty ? null : _carburant,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14), hintText: '⛽ Carburant'),
                items: ['Essence', 'Diesel', 'Électrique', 'Hybride'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _carburant = v ?? ''),
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _input(_localisationCtrl, '📍 Localisation')),
              const SizedBox(width: 12),
              Expanded(child: _input(_couleurCtrl, '🎨 Couleur')),
            ]),
            const SizedBox(height: 12),
            _input(_documentsCtrl, '📄 Documents (Plaque, Douane, CNRC...)'),
            const SizedBox(height: 12),
            Row(children: [
              _checkbox('Prix négociable', _prixNegociable, (v) => setState(() => _prixNegociable = v)),
              _checkbox('Livraison', _livraison, (v) => setState(() => _livraison = v)),
              _checkbox('Garantie', _garantie, (v) => setState(() => _garantie = v)),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _publishing ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6F00),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _publishing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Publier', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox(String label, bool value, Function(bool) onChanged) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(children: [
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank, color: value ? const Color(0xFFFF6F00) : Colors.grey, size: 20),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return TextField(
      controller: ctrl, keyboardType: keyboard, maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint, border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

// ─── MESSAGES TAB (Real Firestore Conversations) ───
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});
  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Center(child: Text('Connectez-vous pour voir vos messages', style: TextStyle(color: Colors.grey)));
    }
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: Colors.white,
            child: const Row(
              children: [
                Text('Messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Spacer(),
                Icon(Icons.search, color: Colors.grey),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: _user!.uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF1677FF)));
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 60, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('Erreur de chargement', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('${snap.error}', style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('Aucune conversation', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Contactez un vendeur pour commencer', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  );
                }
                final chats = snap.data!.docs;
                // Sort locally by lastMessageTime
                chats.sort((a, b) {
                  final aTime = (a.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                  final bTime = (b.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });
                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, i) {
                    final data = chats[i].data() as Map<String, dynamic>;
                    final chatId = chats[i].id;
                    final sellerName = data['seller_name'] ?? 'Vendeur';
                    final productName = data['product_name'] ?? '';
                    final lastMsg = data['lastMessage'] ?? '';
                    final sellerId = data['seller_id'] ?? '';
                    final ts = data['lastMessageTime'] as Timestamp?;
                    final time = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1677FF).withOpacity( 0.1),
                        child: Text(sellerName.isNotEmpty ? sellerName[0].toUpperCase() : 'V',
                            style: const TextStyle(color: Color(0xFF1677FF), fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(sellerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                          Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (productName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(productName, style: const TextStyle(fontSize: 11, color: Color(0xFF1677FF))),
                          ],
                          const SizedBox(height: 2),
                          Text(lastMsg, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => AlibabaChatScreen(
                          chatId: chatId,
                          sellerName: sellerName,
                          sellerId: sellerId,
                          productName: productName,
                        )));
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PROFILE TAB ───
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  User? get _user => FirebaseAuth.instance.currentUser;
  String _plan = 'commission';
  double _commissionRate = 1;
  String _subscriptionStatus = 'trial';
  DateTime? _trialEnd;

  @override
  void initState() {
    super.initState();
    _loadVendorInfo();
  }

  Future<void> _loadVendorInfo() async {
    if (_user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('vendeurs').doc(_user!.uid).get();
      if (doc.exists) {
        final d = doc.data()!;
        setState(() {
          _plan = d['plan'] ?? 'commission';
          _commissionRate = (d['commission_rate'] ?? 8).toDouble();
          _subscriptionStatus = d['subscription_status'] ?? 'trial';
          final te = d['trial_end'];
          if (te is String) _trialEnd = DateTime.tryParse(te);
        });
      }
    } catch (e) {}
  }

  String _getPlanLabel() {
    if (_subscriptionStatus == 'trial') return 'Essai gratuit';
    if (_plan == 'abonnement') return 'Abonnement · 5\$/mois';
    return 'Commission · 8% par vente';
  }

  Color _getPlanColor() {
    if (_subscriptionStatus == 'trial') return Colors.green;
    if (_plan == 'abonnement') return const Color(0xFF1677FF);
    return Colors.orange;
  }

  String _getTrialInfo() {
    if (_subscriptionStatus != 'trial' || _trialEnd == null) return '';
    final remaining = _trialEnd!.difference(DateTime.now()).inDays;
    if (remaining <= 0) return 'Essai expire';
    return '$remaining jours restants';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF1677FF).withOpacity( 0.1),
              child: _user?.photoURL != null
                  ? ClipOval(child: Image.network(_user!.photoURL!, width: 80, height: 80, fit: BoxFit.cover))
                  : const Icon(Icons.person, size: 40, color: Color(0xFF1677FF)),
            ),
            const SizedBox(height: 12),
            Text(_user?.displayName ?? 'Mon Compte',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(_user?.email ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),

            // Plan card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getPlanColor().withOpacity( 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _getPlanColor().withOpacity( 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium, color: _getPlanColor(), size: 20),
                      const SizedBox(width: 8),
                      Text(_getPlanLabel(), style: TextStyle(color: _getPlanColor(), fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  if (_getTrialInfo().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_getTrialInfo(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _showPlanChoicePopup(),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: _getPlanColor())),
                      child: Text('Gerer mon plan', style: TextStyle(color: _getPlanColor())),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _tile(Icons.shopping_bag_outlined, 'Mes commandes', onTap: () => _showOrders(context)),
            _tile(Icons.store_outlined, 'Ma boutique', onTap: () => _showMyProducts(context)),
            _tile(Icons.favorite_outline, 'Mes favoris', onTap: () => _showFavorites(context)),
            _tile(Icons.location_on_outlined, 'Adresses', onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gestion des adresses bientot disponible')));
            }),
            _tile(Icons.settings_outlined, 'Parametres', onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parametres bientot disponibles')));
            }),
            _tile(Icons.help_outline, 'Aide', onTap: () => _showHelp(context)),
            const SizedBox(height: 16),

            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Se deconnecter', style: TextStyle(color: Colors.red, fontSize: 14)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlanChoicePopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text('Choisir un plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Choisissez comment payer les commissions', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),

              // Commission plan
              _planOption(
                title: 'Commission',
                subtitle: '8% par vente',
                price: 'Gratuit a l\'inscription',
                desc: 'Pas de frais fixes. Vous payez seulement 8% sur chaque vente.',
                icon: Icons.percent,
                color: Colors.orange,
                isSelected: _plan == 'commission' && _subscriptionStatus != 'trial',
                onTap: () async {
                  await _switchPlan('commission', 1);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadVendorInfo();
                },
              ),
              const SizedBox(height: 12),

              // Abonnement plan
              _planOption(
                title: 'Abonnement',
                subtitle: '5\$/mois',
                price: '5\$ / mois',
                desc: 'Zéro commission. Payez un forfait mensuel fixe.',
                icon: Icons.star_outline,
                color: const Color(0xFF1677FF),
                isSelected: _plan == 'abonnement',
                onTap: () async {
                  await _switchPlan('abonnement', 0);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadVendorInfo();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planOption({
    required String title,
    required String subtitle,
    required String price,
    required String desc,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity( 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity( 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text(subtitle, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 22)
            else
              Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _switchPlan(String plan, double commissionRate) async {
    if (_user == null) return;
    try {
      await FirebaseFirestore.instance.collection('vendeurs').doc(_user!.uid).update({
        'plan': plan,
        'commission_rate': commissionRate,
        'subscription_status': plan == 'abonnement' ? 'active' : 'active',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(plan == 'abonnement'
              ? 'Abonnement active ! 0% commission'
              : 'Plan Commission active ! 8% par vente')),
        );
      }
    } catch (e) {
      debugPrint('Switch plan error: $e');
    }
  }

  Future<void> _showOrders(BuildContext context) async {
    if (_user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Mes commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .where('user_id', isEqualTo: _user!.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const Center(child: Text('Aucune commande', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: snap.data!.docs.length,
                    itemBuilder: (ctx, i) {
                      final data = snap.data!.docs[i].data() as Map<String, dynamic>;
                      final status = data['status'] ?? 'en_attente';
                      final price = data['price'] ?? 0;
                      final method = data['payment_method'] ?? '';
                      return ListTile(
                        leading: Icon(
                          status == 'livre' ? Icons.check_circle : Icons.access_time,
                          color: status == 'livre' ? Colors.green : Colors.orange,
                        ),
                        title: Text('\$${(price as num).toDouble().toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$method - $status'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMyProducts(BuildContext context) async {
    if (_user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Ma boutique', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('products')
                    .where('seller_id', isEqualTo: _user!.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const Center(child: Text('Aucun produit publie', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: snap.data!.docs.length,
                    itemBuilder: (ctx, i) {
                      final data = snap.data!.docs[i].data() as Map<String, dynamic>;
                      final titre = data['titre'] ?? 'Produit';
                      final price = data['price'] ?? 0;
                      final statut = data['statut'] ?? '';
                      return ListTile(
                        leading: const Icon(Icons.shopping_bag, color: Color(0xFF1677FF)),
                        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('\$${(price as num).toDouble().toStringAsFixed(2)} - $statut'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFavorites(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mes favoris bientot disponible')));
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Aide & Support', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.help_outline, color: Color(0xFF1677FF)),
              title: const Text('FAQ'),
              subtitle: const Text('Questions frequentes'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined, color: Color(0xFF1677FF)),
              title: const Text('Contacter le support'),
              subtitle: const Text('support@easymarket.com'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF1677FF)),
              title: const Text('A propos'),
              subtitle: const Text('Easy Market v1.0.0'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1677FF)),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap ?? () {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// NOTIFICATIONS SCREEN — Centre de notifications style Alibaba
// ═══════════════════════════════════════════════════════════════
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all'; // all, new_product, new_vendor, order, system
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(user.uid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      _notifications = snap.docs.map((d) => {'_id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error loading notifs: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _markAsRead(String notifId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(user.uid)
        .collection('items')
        .doc(notifId)
        .update({'read': true});
  }

  Future<void> _markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(user.uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
    _loadNotifications();
  }

  List<Map<String, dynamic>> get _filteredNotifs {
    if (_filter == 'all') return _notifications;
    return _notifications.where((n) => n['type'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _markAllAsRead,
            child: const Text('Tout marquer lu', style: TextStyle(color: Color(0xFF1677FF), fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtres
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip('Tout', 'all'),
                _filterChip('Nouveautes', 'new_product'),
                _filterChip('Vendeurs', 'new_vendor'),
                _filterChip('Commandes', 'order'),
                _filterChip('Systeme', 'system'),
              ],
            ),
          ),
          const Divider(height: 1),
          // Liste
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredNotifs.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Aucune notification', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.builder(
                          itemCount: _filteredNotifs.length,
                          itemBuilder: (ctx, i) => _notifTile(_filteredNotifs[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1677FF) : const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notifTile(Map<String, dynamic> notif) {
    final type = notif['type'] ?? '';
    final read = notif['read'] == true;
    IconData icon;
    Color iconColor;

    switch (type) {
      case 'new_product':
        icon = Icons.inventory_2_outlined;
        iconColor = const Color(0xFFFF6A00);
        break;
      case 'new_vendor':
        icon = Icons.store_outlined;
        iconColor = const Color(0xFF1677FF);
        break;
      case 'order':
        icon = Icons.shopping_bag_outlined;
        iconColor = const Color(0xFF52C41A);
        break;
      default:
        icon = Icons.info_outline;
        iconColor = Colors.grey;
    }

    return Container(
      color: read ? Colors.white : const Color(0xFFF6F9FF),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          notif['title'] ?? '',
          style: TextStyle(
            fontWeight: read ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          notif['body'] ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: !read
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF1677FF),
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () async {
          await _markAsRead(notif['_id']);
          setState(() => notif['read'] = true);
          // Navigation selon le type
          if (type == 'new_product' && notif['productId'] != null) {
            // Ouvrir le produit
          } else if (type == 'new_vendor' && notif['vendorId'] != null) {
            // Ouvrir le vendeur
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// FOLLOW / UNFollow VENDEUR
// ═══════════════════════════════════════════════════════════════
class FollowButton extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  const FollowButton({super.key, required this.sellerId, required this.sellerName});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _isFollowing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkFollowing();
  }

  Future<void> _checkFollowing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('followers')
        .doc('${user.uid}_${widget.sellerId}')
        .get();
    if (mounted) setState(() { _isFollowing = doc.exists; _loading = false; });
  }

  Future<void> _toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final docId = '${user.uid}_${widget.sellerId}';
    final ref = FirebaseFirestore.instance.collection('followers').doc(docId);

    if (_isFollowing) {
      await ref.delete();
      if (mounted) setState(() { _isFollowing = false; _loading = false; });
    } else {
      final token = await FirebaseMessaging.instance.getToken();
      await ref.set({
        'userId': user.uid,
        'sellerId': widget.sellerId,
        'sellerName': widget.sellerName,
        'token': token,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() { _isFollowing = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 80, height: 32, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))));
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isFollowing ? Colors.grey[200] : const Color(0xFF1677FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFollowing ? Icons.check : Icons.add,
              size: 16,
              color: _isFollowing ? Colors.black87 : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              _isFollowing ? 'Suivi' : 'Suivre',
              style: TextStyle(
                color: _isFollowing ? Colors.black87 : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
