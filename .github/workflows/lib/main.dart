import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

// Change this to your server address (use https:// in production).
// 10.0.2.2 reaches your computer from the Android emulator.
const String kBaseUrl = 'http://10.0.2.2:3000';
const String kAppName = 'Play MAX';

// Colors: deep navy background, electric blue primary, amber highlights.
const Color kBg = Color(0xFF070B1A);
const Color kSurface = Color(0xFF101A3C);
const Color kBlue = Color(0xFF2F6BFF);
const Color kAmber = Color(0xFFFFB400);

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, this.status);
  @override
  String toString() => message;
}

// Firebase Authentication through its REST API (only needs the web API key).
class Auth {
  static String? idToken;
  static String? refreshToken;
  static DateTime expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  static final String _key = kFirebaseConfig['apiKey']!;

  static String _friendly(String code) {
    final c = code.split(' ').first;
    switch (c) {
      case 'EMAIL_EXISTS':
        return 'This phone number is already registered. Try signing in.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/Password sign-in is turned off in Firebase. Enable it in Firebase Console > Authentication > Sign-in method.';
      case 'WEAK_PASSWORD':
        return 'Password must be at least 6 characters.';
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'INVALID_PASSWORD':
      case 'EMAIL_NOT_FOUND':
        return 'Wrong phone number or password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Try again in a few minutes.';
      case 'CONFIGURATION_NOT_FOUND':
        return 'Firebase Authentication is not set up for this project yet. Open Firebase Console > Authentication and press Get started.';
      case 'API_KEY_INVALID':
      case 'API':
        return 'The Firebase API key is not valid.';
      case 'TOKEN_EXPIRED':
      case 'INVALID_REFRESH_TOKEN':
        return 'Your session has expired. Please sign in again.';
      default:
        return 'Sign-in failed ($code).';
    }
  }

  static Future<Map<String, dynamic>> _post(Uri uri, Object body) async {
    http.Response r;
    try {
      r = await http.post(uri, body: body is String ? body : null, headers: body is String ? {'Content-Type': 'application/json'} : null).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiError('Cannot reach the server. Check your internet connection.', 0);
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiError(_friendly('${data['error']?['message'] ?? 'UNKNOWN'}'), r.statusCode);
    }
    return data;
  }

  static Future<void> _store(String id, String refresh, String expiresIn) async {
    idToken = id;
    refreshToken = refresh;
    expiresAt = DateTime.now().add(Duration(seconds: (int.tryParse(expiresIn) ?? 3600) - 60));
    (await SharedPreferences.getInstance()).setString('refreshToken', refresh);
  }

  static Future<void> _signWith(String endpoint, String phone, String password) async {
    final d = await _post(
      Uri.parse('https://identitytoolkit.googleapis.com/v1/$endpoint?key=$_key'),
      jsonEncode({'email': '$phone$kEmailDomain', 'password': password, 'returnSecureToken': true}),
    );
    await _store(d['idToken'], d['refreshToken'], '${d['expiresIn']}');
  }

  static Future<void> signUp(String phone, String password) => _signWith('accounts:signUp', phone, password);
  static Future<void> signIn(String phone, String password) => _signWith('accounts:signInWithPassword', phone, password);

  // Returns false when there is no saved session or it can no longer be refreshed.
  static Future<bool> refresh() async {
    refreshToken ??= (await SharedPreferences.getInstance()).getString('refreshToken');
    if (refreshToken == null) return false;
    try {
      final r = await http
          .post(Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_key'), body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken!})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode >= 400) {
        await signOut();
        return false;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      await _store(d['id_token'], d['refresh_token'], '${d['expires_in']}');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() async {
    idToken = null;
    refreshToken = null;
    (await SharedPreferences.getInstance()).remove('refreshToken');
  }
}

class Api {
  static Future<dynamic> call(String method, String path, {Map<String, dynamic>? body}) async {
    if (Auth.idToken == null || DateTime.now().isAfter(Auth.expiresAt)) await Auth.refresh();
    var r = await _send(method, path, body);
    if (r.statusCode == 401 && await Auth.refresh()) r = await _send(method, path, body);
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      throw ApiError((data is Map ? data['error'] : null) ?? 'Request failed', r.statusCode);
    }
    return data;
  }

  static Future<http.Response> _send(String method, String path, Map<String, dynamic>? body) async {
    final uri = Uri.parse('$kBaseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (Auth.idToken != null) 'Authorization': 'Bearer ${Auth.idToken}',
    };
    try {
      return method == 'POST'
          ? await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 15))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiError('Cannot reach the server. Check your internet connection.', 0);
    }
  }
}

final ValueNotifier<Map<String, dynamic>?> me = ValueNotifier(null);

Future<void> refreshMe() async {
  me.value = Map<String, dynamic>.from(await Api.call('GET', '/api/me'));
}

void main() => runApp(const PlayMaxApp());

class PlayMaxApp extends StatelessWidget {
  const PlayMaxApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kBlue, brightness: Brightness.dark).copyWith(
      primary: kBlue,
      onPrimary: Colors.white,
      secondary: kAmber,
      surface: kBg,
      surfaceContainerLow: kSurface,
      secondaryContainer: const Color(0xFF3A2E00),
      onSecondaryContainer: Colors.white,
    );
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0, scrolledUnderElevation: 0),
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: kSurface, indicatorColor: Color(0x662F6BFF)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
      home: const Boot(),
    );
  }
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    Widget next = const AuthPage();
    if (await Auth.refresh()) {
      try {
        await refreshMe();
        next = const Shell();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> signOutAndGo(BuildContext context) async {
  await Auth.signOut();
  me.value = null;
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (r) => false);
}

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(colors: [kBlue, Color(0xFF0B2A8F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(Icons.sports_esports, color: Colors.white, size: size * 0.55),
      );
}

// ---------------- Sign in / Create account ----------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool register = false, busy = false, showPass = false;
  final phone = TextEditingController(), name = TextEditingController(), pass = TextEditingController(), ref = TextEditingController();

  Future<void> submit() async {
    final p = phone.text.replaceAll(RegExp(r'\s+'), '');
    if (register && name.text.trim().isEmpty) return snack(context, 'Enter your name.');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(p)) return snack(context, 'Enter a valid phone number.');
    if (pass.text.length < 6) return snack(context, 'Password must be at least 6 characters.');
    setState(() => busy = true);
    try {
      if (register) {
        await Auth.signUp(p, pass.text);
        await Api.call('POST', '/api/profile', body: {'name': name.text.trim()});
        if (ref.text.trim().isNotEmpty) {
          try {
            await Api.call('POST', '/api/referral', body: {'code': ref.text.trim()});
          } on ApiError catch (e) {
            if (mounted) snack(context, 'Account created. Referral code not applied: ${e.message}');
          }
        }
      } else {
        await Auth.signIn(p, pass.text);
      }
      await refreshMe();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B1B4D), kBg], begin: Alignment.topCenter, end: Alignment.center)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: Logo(size: 76)),
                  const SizedBox(height: 14),
                  Text(kAppName.toUpperCase(), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  const Text('Fair tournaments. Real competition.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true, label: Text('Create account')),
                    ],
                    selected: {register},
                    onSelectionChanged: busy ? null : (s) => setState(() => register = s.first),
                  ),
                  const SizedBox(height: 20),
                  Text(register ? 'Welcome, sign up' : 'Welcome back', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  if (register) ...[
                    TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline))),
                    const SizedBox(height: 12),
                  ],
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: !showPass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: TextButton(onPressed: () => setState(() => showPass = !showPass), child: Text(showPass ? 'Hide' : 'Show')),
                    ),
                  ),
                  if (register) ...[
                    const SizedBox(height: 12),
                    TextField(controller: ref, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code (optional)', prefixIcon: Icon(Icons.card_giftcard))),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(register ? 'Create account' : 'Sign in', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Shell with bottom navigation ----------------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  void go(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[HomePage(go: go), const PlayPage(), const MyMatchesPage(), const WalletPage(), const ProfilePage()];
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Logo(size: 30), SizedBox(width: 10), Text(kAppName, style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [
          ValueListenableBuilder(
            valueListenable: me,
            builder: (_, m, __) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(avatar: const Icon(Icons.monetization_on, size: 18, color: kAmber), label: Text('${m?['coins'] ?? 0}')),
            ),
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Play'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'My matches'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- Home dashboard ----------------
class HomePage extends StatefulWidget {
  final void Function(int) go;
  const HomePage({super.key, required this.go});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final pager = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  Widget banner(List<Color> colors, IconData icon, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(sub, style: const TextStyle(color: Colors.white70)),
                ]),
              ),
              Icon(icon, size: 72, color: Colors.white30),
            ]),
          ),
        ),
      );

  Widget tile(IconData icon, Color color, String label, String sub, VoidCallback onTap) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(icon, color: color, size: 30),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white60)),
              ]),
            ]),
          ),
        ),
      );

  void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      ValueListenableBuilder(
        valueListenable: me,
        builder: (_, m, __) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, ${m?['name'] ?? 'player'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text('Ready for the next match?', style: TextStyle(color: Colors.white60)),
          ]),
        ),
      ),
      SizedBox(
        height: 150,
        child: PageView(controller: pager, children: [
          banner([const Color(0xFF1740C9), const Color(0xFF0B1B4D)], Icons.sports_esports, 'Welcome to Play MAX', 'Join tournaments and win coins.', () => widget.go(1)),
          banner([const Color(0xFF0F7A5C), const Color(0xFF0B2B3A)], Icons.emoji_events, 'Free Fire tournaments', 'Pick a match and join in seconds.', () => widget.go(1)),
          banner([const Color(0xFFB36B00), const Color(0xFF3A2200)], Icons.card_giftcard, 'Refer and earn', 'Invite friends. You both get coins.', () => open(const ReferPage())),
        ]),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text('Quick access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.45,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          tile(Icons.sports_esports, kBlue, 'Play', 'Join a tournament', () => widget.go(1)),
          tile(Icons.list_alt, Colors.tealAccent, 'My matches', 'Rooms and results', () => widget.go(2)),
          tile(Icons.emoji_events, kAmber, 'Leaderboard', 'Top players', () => open(Scaffold(appBar: AppBar(title: const Text('Leaderboard')), body: const LeaderboardPage()))),
          tile(Icons.card_giftcard, Colors.pinkAccent, 'Refer and earn', 'Invite friends', () => open(const ReferPage())),
          tile(Icons.account_balance_wallet, Colors.lightGreenAccent, 'Wallet', 'Coins and history', () => widget.go(3)),
          tile(Icons.person, Colors.white70, 'Profile', 'Your account', () => widget.go(4)),
        ],
      ),
    ]);
  }
}

// ---------------- Profile ----------------
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: me,
      builder: (c, m, _) {
        final name = '${m?['name'] ?? ''}';
        return ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: CircleAvatar(radius: 40, backgroundColor: kBlue, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)))),
          const SizedBox(height: 12),
          Center(child: Text(name, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          Center(child: Text('${m?['phone'] ?? ''}', style: const TextStyle(color: Colors.white60))),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.card_giftcard, color: kAmber),
              title: const Text('Refer and earn'),
              subtitle: Text('Your code: ${m?['referral_code'] ?? '...'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const ReferPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.emoji_events, color: kAmber),
              title: const Text('Leaderboard'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Leaderboard')), body: const LeaderboardPage()))),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => signOutAndGo(c), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ]);
      },
    );
  }
}

// ---------------- Refer and earn ----------------
class ReferPage extends StatefulWidget {
  const ReferPage({super.key});
  @override
  State<ReferPage> createState() => _ReferPageState();
}

class _ReferPageState extends State<ReferPage> {
  final code = TextEditingController();
  bool busy = false;

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      final d = await Api.call('POST', '/api/referral', body: {'code': code.text.trim()});
      await refreshMe();
      if (mounted) snack(context, 'Code applied. You got ${d['bonus']} coins.');
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refer and earn')),
      body: ValueListenableBuilder(
        valueListenable: me,
        builder: (c, m, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Invite friends. When they sign up with your code, you both get ${m?['referral_bonus'] ?? 0} coins.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Your referral code', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 6),
                SelectableText('${m?['referral_code'] ?? '...'}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4, color: kAmber)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${m?['referral_code'] ?? ''}'));
                    snack(c, 'Code copied');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                ),
                Text('${m?['referrals'] ?? 0} friends joined with your code', style: const TextStyle(color: Colors.white60)),
              ]),
            ),
          ),
          if (m?['has_referrer'] != true) ...[
            const SizedBox(height: 20),
            const Text('Have a friend\'s code?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code')),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : apply, child: const Padding(padding: EdgeInsets.all(10), child: Text('Apply code'))),
            const SizedBox(height: 6),
            const Text('Codes can only be used once, before your first match.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ]),
      ),
    );
  }
}

// A small helper that loads a list and supports pull-to-refresh.
class AsyncList extends StatefulWidget {
  final String path;
  final String empty;
  final Widget Function(BuildContext, Map<String, dynamic>) item;
  const AsyncList({super.key, required this.path, required this.empty, required this.item});
  @override
  State<AsyncList> createState() => _AsyncListState();
}

class _AsyncListState extends State<AsyncList> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() async => (await Api.call('GET', widget.path)) as List<dynamic>;
  Future<void> _reload() async {
    setState(() => future = _load());
    await future.catchError((_) => <dynamic>[]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${s.error}'),
            TextButton(onPressed: _reload, child: const Text('Try again')),
          ]));
        }
        final items = s.data!;
        return RefreshIndicator(
          onRefresh: _reload,
          child: items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(widget.empty)))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (c, i) => widget.item(c, Map<String, dynamic>.from(items[i])),
                ),
        );
      },
    );
  }
}

String when(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day}/${d.month}/${d.year}  $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

// ---------------- Home: match lists ----------------
class PlayPage extends StatelessWidget {
  const PlayPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'Live'), Tab(text: 'Results')]),
        Expanded(
          child: TabBarView(children: [
            _list('upcoming', 'No upcoming matches right now. Pull down to refresh.'),
            _list('live', 'No live matches right now.'),
            _list('completed', 'No results yet.'),
          ]),
        ),
      ]),
    );
  }

  Widget _list(String status, String empty) => AsyncList(
        path: '/api/matches?status=$status',
        empty: empty,
        item: (c, m) => Card(
          child: ListTile(
            title: Text(m['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${m['game']} · ${m['mode']}\n${when(m['starts_at'])}\nEntry ${m['entry_fee']} · Prize ${m['prize_pool']} · ${m['joined']}/${m['max_players']} joined'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => MatchPage(id: m['id']))),
          ),
        ),
      );
}

// ---------------- Match detail + join ----------------
class MatchPage extends StatefulWidget {
  final int id;
  const MatchPage({super.key, required this.id});
  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  late Future<dynamic> future = Api.call('GET', '/api/matches/${widget.id}');
  bool busy = false;

  Future<void> join(Map m) async {
    final ctrl = TextEditingController(text: me.value?['name'] ?? '');
    final ign = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Join this match'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Entry fee: ${m['entry_fee']} coins'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Your in-game name', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Pay and join')),
        ],
      ),
    );
    if (ign == null || ign.isEmpty) return;
    setState(() => busy = true);
    try {
      await Api.call('POST', '/api/matches/${widget.id}/join', body: {'ingame_name': ign});
      await refreshMe();
      if (!mounted) return;
      snack(context, 'You joined the match');
      setState(() => future = Api.call('GET', '/api/matches/${widget.id}'));
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: FutureBuilder<dynamic>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return Center(child: Text('${s.error}'));
          final m = Map<String, dynamic>.from(s.data);
          final players = (m['players'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
          final open = m['status'] == 'upcoming' && m['joined'] < m['max_players'] && m['joined_by_me'] != true;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(m['title'], style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${m['game']} · ${m['mode']} · ${m['status']}'),
            Text(when(m['starts_at'])),
            const SizedBox(height: 12),
            Row(children: [
              _stat('Entry', '${m['entry_fee']}'),
              _stat('Prize pool', '${m['prize_pool']}'),
              _stat('Players', '${m['joined']}/${m['max_players']}'),
            ]),
            const SizedBox(height: 16),
            if (m['joined_by_me'] == true)
              Card(
                color: Theme.of(c).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('You are in as ${m['my_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (m['room_id'] != null && '${m['room_id']}'.isNotEmpty) ...[
                      SelectableText('Room ID: ${m['room_id']}'),
                      SelectableText('Password: ${m['room_pass'] ?? ''}'),
                    ] else
                      const Text('Room details will appear here before the match starts.'),
                  ]),
                ),
              ),
            if (open)
              FilledButton(
                onPressed: busy ? null : () => join(m),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(m['entry_fee'] == 0 ? 'Join for free' : 'Join for ${m['entry_fee']} coins')),
              ),
            if (m['status'] == 'upcoming' && m['joined'] >= m['max_players'] && m['joined_by_me'] != true) const Text('This match is full.'),
            const SizedBox(height: 20),
            Text(m['status'] == 'completed' ? 'Results' : 'Players', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (players.isEmpty) const Text('Nobody has joined yet.'),
            for (final p in players)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p['ingame_name']),
                trailing: m['status'] == 'completed' ? Text('${p['kills']} kills · ${p['prize']} coins') : null,
              ),
          ]);
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
}

// ---------------- My matches ----------------
class MyMatchesPage extends StatelessWidget {
  const MyMatchesPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncList(
        path: '/api/my-matches',
        empty: 'You have not joined any match yet.',
        item: (c, m) => Card(
          child: ListTile(
            title: Text(m['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${m['ingame_name']} · ${m['status']}\n${when(m['starts_at'])}'),
            isThreeLine: true,
            trailing: m['status'] == 'completed' ? Text('${m['prize']} coins') : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => MatchPage(id: m['id']))),
          ),
        ),
      );
}

// ---------------- Leaderboard ----------------
class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncList(
        path: '/api/leaderboard',
        empty: 'The leaderboard fills up after the first match ends.',
        item: (c, p) => Card(
          child: ListTile(
            title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p['matches']} matches · ${p['kills']} kills'),
            trailing: Text('${p['prize']} coins', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

// ---------------- Wallet ----------------
class WalletPage extends StatelessWidget {
  const WalletPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ValueListenableBuilder(
        valueListenable: me,
        builder: (_, m, __) => Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your coins', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
            Text('${m?['coins'] ?? 0}', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onPrimary)),
          ]),
        ),
      ),
      Expanded(
        child: AsyncList(
          path: '/api/transactions',
          empty: 'No transactions yet.',
          item: (c, t) {
            final amt = t['amount'] as int;
            return ListTile(
              title: Text(t['note'] ?? t['kind']),
              subtitle: Text(when('${t['created_at']}Z'.replaceFirst(' ', 'T'))),
              trailing: Text(amt > 0 ? '+$amt' : '$amt', style: TextStyle(fontWeight: FontWeight.w800, color: amt > 0 ? Colors.greenAccent : Colors.redAccent)),
            );
          },
        ),
      ),
    ]);
  }
}
