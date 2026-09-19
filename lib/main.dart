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

// â”€â”€ Colours â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const Color kGold      = Color(0xFFF5E6C8);
const Color kBg        = Color(0xFF121212);
const Color kStageTop  = Color(0xFFFBAB72); // orange stage top
const Color kStageBot  = Color(0xFFF4935A); // orange stage bottom
const Color kFormCard  = Color(0xFF1E1A16);
const Color kField     = Color(0xFFFDF0DC);
const Color kFieldText = Color(0xFF3B2A1E);
const Color kLoginBtn  = Color(0xFFEF4030);

// â”€â”€ Constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const String kUrl = 'https://aniketsarker.netlify.app';
const String kSheetUrl =
    'https://script.google.com/macros/s/AKfycbysLY93ie5plvuUrv42-E9vxG9IWcDImkuj-fUv3jg4tqSvyPcz0H1yZlkrocNFIiDO/exec';
const String kMasterKey = 'atp1726';
const MethodChannel _galleryChannel    = MethodChannel('aniket_pro_ai/gallery');
const MethodChannel _screenshotChannel = MethodChannel('aniket_pro_ai/screenshot');

// â”€â”€ HTTP helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€ Entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  GATE SCREEN  â€”  animated login (orange stage + walking character)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with TickerProviderStateMixin {

  // â”€â”€ app-logic state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _stage    = 'loading'; // loading | connect | wait | perms | main
  String _deviceId = '';
  bool   _owner      = false;
  bool   _permsAsked = false;
  bool   _permsAsking = false;
  String _myId    = '';
  int    _logoTaps = 0;
  Timer? _poll;
  final _fbCtrl  = TextEditingController();
  final _gmCtrl  = TextEditingController();
  final _fbFocus = FocusNode();
  final _gmFocus = FocusNode();

  // â”€â”€ animation controllers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late final AnimationController _walkCtrl; // character slides in
  late final AnimationController _legCtrl;  // leg swing while walking
  late final AnimationController _dropCtrl; // briefcase drop lean
  late final AnimationController _formCtrl; // form slide-in
  late final AnimationController _waveCtrl; // greeting arm wave (loops)

  late final Animation<double> _charSlide;
  late final Animation<double> _legSwing;
  late final Animation<double> _dropLean;
  late final Animation<double> _formSlide;
  late final Animation<double> _formOpacity;
  late final Animation<double> _waveAngle;

  bool _walking     = false;
  bool _dropped     = false;
  bool _caseOnFloor = false;

  // â”€â”€ lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  void initState() {
    super.initState();

    _walkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    _charSlide = Tween<double>(begin: -1.4, end: 0.0)
        .chain(CurveTween(curve: Curves.linear))
        .animate(_walkCtrl);

    // _legCtrl started only when walking begins (not here)
    _legCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _legSwing = Tween<double>(begin: -0.45, end: 0.45)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_legCtrl);

    _dropCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _dropLean = Tween<double>(begin: 0, end: 0.38)
        .chain(CurveTween(curve: const _BumpCurve()))
        .animate(_dropCtrl);

    _formCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _formSlide = Tween<double>(begin: 60, end: 0)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_formCtrl);
    _formOpacity = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_formCtrl);

    // wave loops continuously; only affects render when isGreeting=true
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _waveAngle = Tween<double>(begin: -1.52, end: -1.28)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_waveCtrl);

    _fbFocus.addListener(() => setState(() {}));
    _gmFocus.addListener(() => setState(() {}));

    _boot();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _fbCtrl.dispose();
    _gmCtrl.dispose();
    _fbFocus.dispose();
    _gmFocus.dispose();
    _walkCtrl.dispose();
    _legCtrl.dispose();
    _dropCtrl.dispose();
    _formCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ auth logic (unchanged) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    _owner      = p.getBool('owner')      ?? false;
    _permsAsked = p.getBool('permsAsked') ?? false;
    _myId       = p.getString('myId')     ?? '';
    try {
      _deviceId = (await _galleryChannel.invokeMethod<String>('deviceId')) ?? '';
    } catch (_) {
      _deviceId = 'unknown';
    }
    if (_owner) { setState(() => _stage = 'main'); return; }
    final approved = p.getBool('approved') ?? false;
    if (approved) {
      setState(() => _stage = _permsAsked ? 'main' : 'perms');
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
        setState(() => _stage = _permsAsked ? 'main' : 'perms');
      } else if (status == 'ban') {
        _poll?.cancel();
        await (await SharedPreferences.getInstance()).setBool('approved', false);
        setState(() => _stage = 'connect');
      } else {
        setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
      }
    } catch (_) {
      setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
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
    setState(() => _stage = 'wait');
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
  }

  Future<void> _pickGmail() async {
    try {
      final acc = await _galleryChannel.invokeMethod<String>('pickGoogleAccount');
      if (acc != null && acc.isNotEmpty) {
        _gmCtrl.text = acc;
        setState(() {});
      } else {
        _gmFocus.requestFocus();
        _toast('No Gmail found â€” type it');
      }
    } catch (_) {
      _gmFocus.requestFocus();
      _toast('No Gmail found â€” type it');
    }
  }

  Future<void> _askPerms() async {
    if (_permsAsking) return;
    _permsAsking = true;
    await Permission.photos.request();
    await Permission.notification.request();
    final p = await SharedPreferences.getInstance();
    await p.setBool('permsAsked', true);
    _permsAsked = true;
    await _httpPost(kSheetUrl,
        {'type': 'perms', 'id': _myId, 'device': _deviceId, 'method': '', 'perms': 'gallery:1,notify:1'});
    _permsAsking = false;
    if (mounted) setState(() => _stage = 'main');
  }

  Future<void> _masterDialog() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Master Key', style: TextStyle(color: kGold)),
        content: TextField(controller: c, obscureText: true, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('X', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('OK', style: TextStyle(color: kGold))),
        ],
      ),
    );
    if (ok == true && c.text == kMasterKey) {
      final p = await SharedPreferences.getInstance();
      await p.setBool('owner', true);
      _owner = true;
      if (mounted) setState(() => _stage = 'main');
    }
  }

  void _toast(String t) {
    try { _galleryChannel.invokeMethod('toast', t); } catch (_) {}
  }

  // â”€â”€ entrance animation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _playEntrance() {
    _walking     = true;
    _dropped     = false;
    _caseOnFloor = false;
    _walkCtrl.reset();
    _dropCtrl.reset();
    _formCtrl.reset();
    _legCtrl.repeat(reverse: true); // start legs only when walking

    _walkCtrl.forward().then((_) async {
      if (!mounted) return;
      setState(() => _walking = false);
      _legCtrl.stop();
      await _dropCtrl.forward();
      if (!mounted) return;
      setState(() { _dropped = true; _caseOnFloor = true; });
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await _formCtrl.forward();
    });
  }

  // â”€â”€ build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    if (_stage == 'main')  return const MainWebViewScreen();
    if (_stage == 'perms') Future.microtask(_askPerms);

    final size = MediaQuery.of(context).size;

    // kick entrance once when connect/wait stage first appears
    if ((_stage == 'connect' || _stage == 'wait') &&
        !_walkCtrl.isAnimating &&
        _walkCtrl.value == 0 &&
        !_dropped) {
      Future.microtask(_playEntrance);
    }

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [

        // dark bg
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B1B1B), kBg, Color(0xFF241A10)],
            ),
          ),
        ),

        SafeArea(
          child: Column(children: [

            const SizedBox(height: 16),

            // logo + title (tap 7Ã— for master key)
            GestureDetector(
              onTap: () {
                _logoTaps++;
                if (_logoTaps >= 7) { _logoTaps = 0; _masterDialog(); }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', width: 36, height: 36),
                  const SizedBox(width: 10),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      children: [
                        TextSpan(text: 'ANIKET ', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'PRO AI',  style: TextStyle(color: kGold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // orange stage
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [kStageTop, kStageBot],
                      ),
                    ),
                    child: Stack(clipBehavior: Clip.none, children: [

                      // floor shadow
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.brown.withOpacity(0.18)],
                            ),
                          ),
                        ),
                      ),

                      // character (rebuilds on every animation tick)
                      AnimatedBuilder(
                        animation: Listenable.merge([_charSlide, _legSwing, _dropLean, _waveAngle]),
                        builder: (_, __) {
                          return Positioned(
                            bottom: 28,
                            left: size.width * 0.22 + (_charSlide.value * size.width),
                            child: _CharacterWidget(
                              legAngle:    _walking ? _legSwing.value : 0,
                              leanAngle:   _dropped ? 0 : _dropLean.value,
                              caseOnFloor: _caseOnFloor,
                              isGreeting:  _dropped,
                              waveAngle:   _waveAngle.value,
                            ),
                          );
                        },
                      ),

                      // form card (only visible after formCtrl animates in)
                      AnimatedBuilder(
                        animation: _formCtrl,
                        builder: (_, child) => Positioned(
                          right: 14, top: 0, bottom: 0,
                          width: math.min(size.width * 0.52, 230),
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(_formSlide.value, 0),
                              child: Opacity(opacity: _formOpacity.value, child: child),
                            ),
                          ),
                        ),
                        child: _buildFormCard(),
                      ),

                    ]),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

          ]),
        ),

        // initial loading overlay
        if (_stage == 'loading')
          Container(
            color: kBg,
            child: const Center(child: CircularProgressIndicator(color: kGold)),
          ),

      ]),
    );
  }

  // â”€â”€ form card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: kFormCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_stage == 'connect') ..._connectFields(),
          if (_stage == 'wait')    ..._waitContent(),
          if (_stage == 'perms')
            const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: kGold)),
        ],
      ),
    );
  }

  List<Widget> _connectFields() => [
    const Text('Register Now',
        style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    const Text('Owner approval needed',
        style: TextStyle(color: Colors.white54, fontSize: 10)),
    const SizedBox(height: 14),
    _field(_fbCtrl, _fbFocus, 'Facebook ID'),
    const SizedBox(height: 10),
    _field(_gmCtrl, _gmFocus, 'Gmail ID',
        suffix: IconButton(
          icon: const Icon(Icons.alternate_email, color: kGold, size: 16),
          onPressed: _pickGmail,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        )),
    const SizedBox(height: 14),
    SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kLoginBtn,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          if (_fbCtrl.text.trim().isEmpty && _gmCtrl.text.trim().isEmpty) return;
          _submit(_fbCtrl.text, _gmCtrl.text);
        },
        child: const Text('NEXT  âžœ',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    ),
  ];

  List<Widget> _waitContent() => [
    const CircularProgressIndicator(color: kGold),
    const SizedBox(height: 12),
    const Text('Waiting for approvalâ€¦',
        style: TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
    const SizedBox(height: 8),
    TextButton(
        onPressed: _checkStatus,
        child: const Text('Retry', style: TextStyle(color: kGold, fontSize: 12))),
  ];

  Widget _field(TextEditingController ctrl, FocusNode focus, String hint, {Widget? suffix}) =>
      TextField(
        controller: ctrl,
        focusNode: focus,
        style: const TextStyle(color: kFieldText, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9B8672), fontSize: 12),
          filled: true,
          fillColor: kField,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: kGold, width: 1.5)),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      );
}

// â”€â”€ Bezier bump curve (0â†’1â†’0 for briefcase drop lean) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _BumpCurve extends Curve {
  const _BumpCurve();
  @override
  double transformInternal(double t) {
    if (t < 0.4) return t / 0.4;
    if (t < 0.6) return 1.0;
    return 1.0 - (t - 0.6) / 0.4;
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  CHARACTER WIDGET â€” CustomPainter
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _CharacterWidget extends StatelessWidget {
  final double legAngle;
  final double leanAngle;
  final bool   caseOnFloor;
  final bool   isGreeting;
  final double waveAngle;

  const _CharacterWidget({
    required this.legAngle,
    required this.leanAngle,
    required this.caseOnFloor,
    required this.isGreeting,
    required this.waveAngle,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    height: 190,
    child: CustomPaint(
      painter: _CharPainter(
        legAngle:    legAngle,
        leanAngle:   leanAngle,
        caseOnFloor: caseOnFloor,
        isGreeting:  isGreeting,
        waveAngle:   waveAngle,
      ),
    ),
  );
}

class _CharPainter extends CustomPainter {
  final double legAngle;
  final double leanAngle;
  final bool   caseOnFloor;
  final bool   isGreeting;
  final double waveAngle;

  const _CharPainter({
    required this.legAngle,
    required this.leanAngle,
    required this.caseOnFloor,
    required this.isGreeting,
    required this.waveAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    final pSkin   = Paint()..color = const Color(0xFFF4C64F);
    final pHair   = Paint()..color = const Color(0xFFE5A72B);
    final pShirt  = Paint()..color = const Color(0xFFBDB8B4);
    final pLegB   = Paint()..color = const Color(0xFF15181D);
    final pLegF   = Paint()..color = const Color(0xFF232830);
    final pShoe   = Paint()..color = const Color(0xFF0A0B0D);
    final pCaseB  = Paint()..color = const Color(0xFF7B4A2B);
    final pCaseD  = Paint()..color = const Color(0xFF5D3620);
    final pClasp  = Paint()..color = const Color(0xFFE0B25A);
    final pShadow = Paint()..color = Colors.brown.withOpacity(0.28);

    // ground shadow
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, size.height - 4), width: 56, height: 10),
        pShadow);

    // whole-body lean pivot
    canvas.save();
    canvas.translate(cx, size.height - 40);
    canvas.rotate(leanAngle);
    canvas.translate(-cx, -(size.height - 40));

    // back leg
    _pivot(canvas, cx - 6, size.height - 75, -legAngle, () {
      _rr(canvas, cx - 14, size.height - 75, 13, 72, 6.5, pLegB);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx - 10, size.height - 7), width: 30, height: 11),
          pShoe);
    });

    // front leg
    _pivot(canvas, cx + 4, size.height - 75, legAngle, () {
      _rr(canvas, cx - 4, size.height - 75, 13, 72, 6.5, pLegF);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + 2, size.height - 7), width: 30, height: 11),
          pShoe);
    });

    // back arm (holds briefcase when not dropped)
    final backArmAngle = isGreeting ? -0.3 : legAngle * 0.6;
    _pivot(canvas, cx, size.height - 108, backArmAngle, () {
      _rr(canvas, cx - 10, size.height - 108, 11, 50, 5.5,
          Paint()..color = const Color(0xFF9F9A96));
      if (!caseOnFloor) _briefcase(canvas, cx - 18, size.height - 62, pCaseB, pCaseD, pClasp);
    });

    // torso
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 22, size.height - 138, 44, 66),
            const Radius.circular(14)),
        pShirt);
    canvas.drawPath(
        Path()
          ..moveTo(cx - 6, size.height - 136)
          ..lineTo(cx + 1, size.height - 108)
          ..lineTo(cx + 8, size.height - 136)
          ..close(),
        Paint()..color = const Color(0xFFEFEAE4));

    // head
    canvas.drawCircle(Offset(cx + 2, size.height - 160), 22, pSkin);
    canvas.drawPath(
        Path()
          ..moveTo(cx - 20, size.height - 163)
          ..quadraticBezierTo(cx - 18, size.height - 183, cx + 4, size.height - 182)
          ..quadraticBezierTo(cx + 22, size.height - 180, cx + 24, size.height - 163)
          ..quadraticBezierTo(cx + 10, size.height - 172, cx - 4, size.height - 170)
          ..close(),
        pHair);
    canvas.drawCircle(Offset(cx + 12, size.height - 157), 2.5,
        Paint()..color = const Color(0xFF3A2A10));
    canvas.drawArc(
        Rect.fromCenter(center: Offset(cx + 16, size.height - 150), width: 14, height: 7),
        0, math.pi, false,
        Paint()
          ..color = const Color(0xFFA5701C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);

    // front arm â€” points & waves at form when greeting
    final frontArmAngle = isGreeting ? waveAngle : -legAngle * 0.6;
    _pivot(canvas, cx, size.height - 108, frontArmAngle, () {
      _rr(canvas, cx - 2, size.height - 108, 11, 50, 5.5,
          Paint()..color = const Color(0xFFD3CEC9));
    });

    canvas.restore(); // end lean

    // briefcase on the floor after drop
    if (caseOnFloor) _briefcase(canvas, cx + 30, size.height - 38, pCaseB, pCaseD, pClasp);
  }

  void _pivot(Canvas c, double px, double py, double angle, VoidCallback draw) {
    c.save();
    c.translate(px, py);
    c.rotate(angle);
    c.translate(-px, -py);
    draw();
    c.restore();
  }

  void _rr(Canvas c, double x, double y, double w, double h, double r, Paint p) =>
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)), p);

  void _briefcase(Canvas c, double x, double y, Paint body, Paint stripe, Paint clasp) {
    c.drawPath(
        Path()
          ..moveTo(x + 5,  y - 8)
          ..lineTo(x + 5,  y - 14)
          ..lineTo(x + 23, y - 14)
          ..lineTo(x + 23, y - 8),
        Paint()
          ..color = const Color(0xFF4D2C17)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    _rr(c, x, y - 8, 28, 22, 4, body);
    c.drawRect(Rect.fromLTWH(x, y + 2, 28, 3), stripe);
    _rr(c, x + 11, y, 6, 5, 1, clasp);
  }

  @override
  bool shouldRepaint(_CharPainter o) =>
      o.legAngle    != legAngle    ||
      o.leanAngle   != leanAngle   ||
      o.caseOnFloor != caseOnFloor ||
      o.isGreeting  != isGreeting  ||
      o.waveAngle   != waveAngle;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  OWNER PANEL
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class OwnerPanelScreen extends StatefulWidget {
  const OwnerPanelScreen({super.key});

  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  List<Map<String, String>> _rows = [];
  bool _busy = false;

  @override
  void initState() { super.initState(); _load(); }

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
    setState(() => _busy = false);
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
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: kGold))],
      ),
      body: _busy && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _rows.isEmpty
              ? const Center(child: Text('No requests yet', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r  = _rows[i];
                    final st = r['status'] ?? '';
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}) ${r['id']}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text('ID: ${r['device']}  â€¢  ${r['method']}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(
                                'Perms: ${(r['perms'] ?? '').isEmpty ? 'â€”' : r['perms']}  â€¢  $st',
                                style: TextStyle(
                                    color: st == 'BANNED'
                                        ? Colors.red
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
                          ],
                        ),
                      ),
                    );
                  }),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  MAIN WEB-VIEW SCREEN  â€” with Log out in settings
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
    if (!(p.getBool('notifAsked') ?? false)) {
      await Permission.notification.request();
      await p.setBool('notifAsked', true);
    }
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
    if (_activeBox == 'none') return 'ðŸ“¸ 0';
    final c = _countOf(_activeBox);
    final m = _max[_activeBox] ?? 0;
    return c >= m ? 'FULL' : 'ðŸ“¸ $c';
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
        if (_activeBox == 'none') { _errPop('âŒ SS disabled â€” select a box'); return; }
        if (_sentIds.contains(id) ||
            _queue.any((q) => q.startsWith('$id|')) ||
            _ledger.any((q) => q.startsWith('$id|'))) return;
        final box = _activeBox;
        final m   = _max[box] ?? 0;
        if (_countOf(box) >= m) { _toast('${box.toUpperCase()} FULL â€” select another box'); return; }
        setState(() { _queue.add('$id|$box|$path'); _ledger.add('$id|$box|$path'); });
        await _saveState();
        _pushState();
        final c = _countOf(box);
        _toast(c >= m ? '${box.toUpperCase()} FULL âœ”' : '${box.toUpperCase()} $c/$m âœ…');
        if (_fg) _flush();
      } else if (call.method == 'onBubbleTap') {
        setState(() => _captureOn = !_captureOn);
        await (await SharedPreferences.getInstance()).setBool('cap', _captureOn);
        _pushState();
        _toast(_captureOn ? 'Capture ON â€” SS will be captured' : 'Capture OFF');
      } else if (call.method == 'onBubbleSelect') {
        setState(() => _activeBox = (call.arguments as String) == 'corr' ? 'none' : call.arguments as String);
        await _saveState();
        _pushState();
        if (_activeBox == 'none') {
          _toast('NO BOX â€” SS will not be saved');
        } else {
          final m = _max[_activeBox] ?? 0;
          _countOf(_activeBox) >= m
              ? _toast('${_activeBox.toUpperCase()} FULL â€” select another box')
              : _toast('${_activeBox.toUpperCase()} select â€” auto-upload ON');
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
    if (failed > 0 && !force) _toast('$failed upload pending â€” retry on open/OKAY');
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
        _toast('Delivered + deleted (HTF box à¦…à¦ªà¦°à¦¿à¦¬à¦°à§à¦¤à¦¿à¦¤ à¦°à¦‡à¦²à§‹)');
      }
      setState(() { _captureOn = false; _autoDelete = false; _overlayShown = false; });
      final p = await SharedPreferences.getInstance();
      await p.setBool('cap', false);
      await p.setBool('ad', false);
      await p.setBool('bubble', false);
      try { await _galleryChannel.invokeMethod('hideBubble'); } catch (_) {}
      _pushState();
      _toast('Round done â€” switches OFF');
      if (_queue.isNotEmpty) _toast('${_queue.length} SS pending â€” will upload on next open');
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
      ok > 0 ? _toast('$ok SS in ${box.toUpperCase()} âœ…') : _toast('Could not add to box âŒ');
    } catch (_) { _toast('Picker unavailable âŒ'); }
  }

  // â”€â”€ NEW: log out â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    for (final k in ['approved', 'owner', 'permsAsked', 'myId',
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
                  '  â€¢  HTF ${_countOf('htf')}/6'
                  '  â€¢  ENTRY ${_countOf('entry')}/4'
                  '  â€¢  Queue: ${_queue.length}',
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

                // â”€â”€ Log out â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }
}
