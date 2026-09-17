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

const Color kGold = Color(0xFFF5E6C8);
const Color kBg = Color(0xFF121212);
const String kUrl = 'https://aniketsarker1726.netlify.app';
const String kSheetUrl = 'https://script.google.com/macros/s/AKfycbysLY93ie5plvuUrv42-E9vxG9IWcDImkuj-fUv3jg4tqSvyPcz0H1yZlkrocNFIiDO/exec';
const String kMasterKey = 'atp1726';
const MethodChannel _galleryChannel = MethodChannel('aniket_pro_ai/gallery');
const MethodChannel _screenshotChannel = MethodChannel('aniket_pro_ai/screenshot');

Future<String> _httpGet(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 10));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<bool> _httpPost(String url, Map<String, String> fields) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    final body = fields.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain();
    return res.statusCode == 200;
  } catch (e) {
    return false;
  } finally {
    client.close();
  }
}

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

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  String _stage = 'loading';
  String _deviceId = '';
  bool _owner = false;
  bool _permsAsked = false;
  bool _permsAsking = false;
  String _myId = '';
  int _logoTaps = 0;
  Timer? _poll;
  final _fbCtrl = TextEditingController();
  final _gmCtrl = TextEditingController();
  final _gmFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gmFocus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final p = await SharedPreferences.getInstance();
    _owner = p.getBool('owner') ?? false;
    _permsAsked = p.getBool('permsAsked') ?? false;
    _myId = p.getString('myId') ?? '';
    try {
      _deviceId = (await _galleryChannel.invokeMethod<String>('deviceId')) ?? '';
    } catch (e) {
      _deviceId = 'unknown';
    }
    if (_owner) {
      setState(() => _stage = 'main');
      return;
    }
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
      final raw = await _httpGet(kSheetUrl);
      final rows = (jsonDecode(raw) as List).cast<List<dynamic>>();
      String status = 'none';
      for (final r in rows) {
        if (r.length < 4) continue;
        final type = r[1].toString();
        final dev = r[3].toString();
        if (dev == _deviceId && (type == 'approve' || type == 'ban')) status = type;
      }
      if (status == 'approve') {
        _poll?.cancel();
        final p = await SharedPreferences.getInstance();
        await p.setBool('approved', true);
        setState(() => _stage = _permsAsked ? 'main' : 'perms');
      } else if (status == 'ban') {
        _poll?.cancel();
        final p = await SharedPreferences.getInstance();
        await p.setBool('approved', false);
        setState(() => _stage = 'connect');
      } else {
        setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
      }
    } catch (e) {
      setState(() => _stage = _myId.isEmpty ? 'connect' : 'wait');
    }
  }

  Future<void> _submit(String fb, String gm) async {
    final id = gm.trim().isNotEmpty ? gm.trim() : fb.trim();
    final method = gm.trim().isNotEmpty ? 'Gmail' : 'Facebook';
    final p = await SharedPreferences.getInstance();
    await p.setString('myId', id);
    _myId = id;
    await _httpPost(kSheetUrl, {'type': 'request', 'id': id, 'device': _deviceId, 'method': method, 'perms': ''});
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
        _toast('No Gmail found — type it');
      }
    } catch (e) {
      _gmFocus.requestFocus();
      _toast('No Gmail found — type it');
    }
  }

  Future<void> _askPerms() async {
    if (_permsAsking) return;
    _permsAsking = true;
    await Permission.photos.request();
    final p = await SharedPreferences.getInstance();
    await p.setBool('permsAsked', true);
    _permsAsked = true;
    await _httpPost(kSheetUrl, {'type': 'perms', 'id': _myId, 'device': _deviceId, 'method': '', 'perms': 'gallery:1'});
    _permsAsking = false;
    setState(() => _stage = 'main');
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('X', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK', style: TextStyle(color: kGold))),
        ],
      ),
    );
    if (ok == true && c.text == kMasterKey) {
      final p = await SharedPreferences.getInstance();
      await p.setBool('owner', true);
      _owner = true;
      setState(() => _stage = 'main');
    }
  }

  void _toast(String t) {
    try {
      _galleryChannel.invokeMethod('toast', t);
    } catch (e) {}
  }

  InputDecoration _dec(String h) => InputDecoration(
        hintText: h,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kGold.withOpacity(0.4))),
      );

  @override
  Widget build(BuildContext context) {
    if (_stage == 'main') return const MainWebViewScreen();
    if (_stage == 'perms') {
      Future.microtask(_askPerms);
    }
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  _logoTaps++;
                  if (_logoTaps >= 7) {
                    _logoTaps = 0;
                    _masterDialog();
                  }
                },
                child: Image.asset('assets/logo.png', width: 120, height: 120),
              ),
              const SizedBox(height: 18),
              const Text('ANIKET PRO AI', style: TextStyle(color: kGold, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              if (_stage == 'loading') const CircularProgressIndicator(color: kGold),
              if (_stage == 'connect') ...[
                TextField(controller: _fbCtrl, decoration: _dec('Connect your Facebook')),
                const SizedBox(height: 14),
                TextField(
                    controller: _gmCtrl,
                    focusNode: _gmFocus,
                    decoration: _dec('Connect your Gmail ID').copyWith(
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.alternate_email, color: kGold),
                            onPressed: _pickGmail,
                          ),
                        )),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kGold),
                    onPressed: () {
                      if (_fbCtrl.text.trim().isEmpty && _gmCtrl.text.trim().isEmpty) return;
                      _submit(_fbCtrl.text, _gmCtrl.text);
                    },
                    child: const Text('Connect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
              if (_stage == 'wait') ...[
                const CircularProgressIndicator(color: kGold),
                const SizedBox(height: 18),
                const Text('Connecting… Owner approval pending', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                TextButton(onPressed: _checkStatus, child: const Text('Retry', style: TextStyle(color: kGold))),
              ],
              if (_stage == 'perms') const CircularProgressIndicator(color: kGold),
            ],
          ),
        ),
      ),
    );
  }
}

class OwnerPanelScreen extends StatefulWidget {
  const OwnerPanelScreen({super.key});
  @override
  State<OwnerPanelScreen> createState() => _OwnerPanelScreenState();
}

class _OwnerPanelScreenState extends State<OwnerPanelScreen> {
  List<Map<String, String>> _rows = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final raw = await _httpGet(kSheetUrl);
      final rows = (jsonDecode(raw) as List).cast<List<dynamic>>();
      final Map<String, Map<String, String>> map = {};
      for (final r in rows) {
        if (r.length < 5) continue;
        final type = r[1].toString();
        final id = r[2].toString();
        final dev = r[3].toString();
        final method = r[4].toString();
        final perms = r.length > 5 ? r[5].toString() : '';
        final e = map.putIfAbsent(dev, () => {'id': '', 'method': '', 'perms': '', 'status': 'PENDING', 'time': ''});
        if (type == 'request') {
          e['id'] = id;
          e['method'] = method;
          e['time'] = r[0].toString();
        }
        if (type == 'perms') e['perms'] = perms;
        if (type == 'approve') e['status'] = 'APPROVED';
        if (type == 'ban') e['status'] = 'BANNED';
      }
      _rows = map.entries.map((e) => {'device': e.key, ...e.value}).toList();
      _rows.sort((a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''));
    } catch (e) {}
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
                    final r = _rows[i];
                    final st = r['status'] ?? '';
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}) ${r['id']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text('ID: ${r['device']}  •  ${r['method']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            Text('Perms: ${(r['perms'] ?? '').isEmpty ? '—' : r['perms']}  •  $st', style: TextStyle(color: st == 'BANNED' ? Colors.red : (st == 'APPROVED' ? Colors.green : Colors.orange), fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                ElevatedButton(onPressed: () => _act(r['device']!, 'approve'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('ADD', style: TextStyle(color: Colors.white))),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: () => _act(r['device']!, 'ban'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('BAN', style: TextStyle(color: Colors.white))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class MainWebViewScreen extends StatefulWidget {
  const MainWebViewScreen({super.key});
  @override
  State<MainWebViewScreen> createState() => _MainWebViewScreenState();
}

class _MainWebViewScreenState extends State<MainWebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final ValueNotifier<double> _progressN = ValueNotifier<double>(1);
  bool _isLoading = true;
  bool _firstLoad = true;
  bool _fg = true;
  bool _flushing = false;
  bool _captureOn = true;
  bool _autoDelete = false;
  bool _overlayShown = false;
  bool _owner = false;
  String _activeBox = 'none';
  String _deviceId = '';
  int _cHtf = 0;
  int _cEntry = 0;
  int _cCorr = 0;
  final List<String> _queue = [];
  final Map<String, int> _siteCount = {'htf': 0, 'entry': 0, 'corr': 0};
  final Map<String, String> _deliveredBox = {};
  final List<String> _deliveredOk = [];
  DateTime _lastErrPop = DateTime(2000);
  Timer? _banTimer;
  VoidCallback? _sheetRefresh;
  static const Map<String, int> _max = {'htf': 6, 'entry': 4, 'corr': 1};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
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

  void _startBanWatch() {
    _banTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_owner) return;
      try {
        if (_deviceId.isEmpty) {
          _deviceId = (await _galleryChannel.invokeMethod<String>('deviceId')) ?? '';
        }
        final raw = await _httpGet(kSheetUrl);
        final rows = (jsonDecode(raw) as List).cast<List<dynamic>>();
        String status = 'none';
        for (final r in rows) {
          if (r.length < 4) continue;
          final type = r[1].toString();
          final dev = r[3].toString();
          if (dev == _deviceId && (type == 'approve' || type == 'ban')) status = type;
        }
        if (status == 'ban') {
          final p = await SharedPreferences.getInstance();
          await p.setBool('approved', false);
          _toast('Access removed by owner');
          if (mounted) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const GateScreen()));
          }
        }
      } catch (e) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fg = true;
      _syncBubble();
      setState(() {});
      _pushState();
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
    } catch (e) {}
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _captureOn = p.getBool('cap') ?? true;
      _autoDelete = p.getBool('ad') ?? false;
      _overlayShown = p.getBool('bubble') ?? false;
      _owner = p.getBool('owner') ?? false;
      _activeBox = (p.getString('abox') ?? 'none');
      if (_activeBox.isEmpty) _activeBox = 'none';
      _cHtf = p.getInt('c_htf') ?? 0;
      _cEntry = p.getInt('c_entry') ?? 0;
      _cCorr = p.getInt('c_corr') ?? 0;
      _queue.clear();
      _queue.addAll(p.getStringList('queue') ?? []);
    });
    _pushState();
  }

  Future<void> _saveCounts() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('c_htf', _cHtf);
    await p.setInt('c_entry', _cEntry);
    await p.setInt('c_corr', _cCorr);
    await p.setString('abox', _activeBox);
    await p.setStringList('queue', _queue);
  }

  int _countOf(String box) => box == 'htf' ? _cHtf : (box == 'entry' ? _cEntry : _cCorr);

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
        'htf': _cHtf,
        'entry': _cEntry,
        'corr': _cCorr,
        'active': _activeBox,
        'capture': _captureOn ? 1 : 0,
      });
    } catch (e) {}
  }

  void _toast(String t) {
    try {
      _galleryChannel.invokeMethod('toast', t);
    } catch (e) {}
  }

  void _errPop(String t) {
    final now = DateTime.now();
    if (now.difference(_lastErrPop).inMilliseconds < 2000) return;
    _lastErrPop = now;
    try {
      _galleryChannel.invokeMethod('errorPop', t);
    } catch (e) {}
  }

  void _initScreenshotListener() {
    _screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        if (_captureOn) {
          final path = call.arguments as String;
          if (_activeBox == 'none') {
            _errPop('❌ SS disabled — select a box');
            return;
          }
          final box = _activeBox;
          final m = _max[box] ?? 0;
          if (_countOf(box) >= m) {
            _toast('${box.toUpperCase()} FULL — select another box');
            return;
          }
          setState(() {
            if (box == 'htf') { _cHtf++; } 
            else if (box == 'entry') { _cEntry++; } 
            else { _cCorr++; }
            _queue.add('$box|$path');
          });
          await _saveCounts();
          _pushState();
          final c = _countOf(box);
          _toast(c >= m ? '${box.toUpperCase()} FULL ✔' : '${box.toUpperCase()} $c/$m ✅');
          if (_fg) _flush();
        }
      } else if (call.method == 'onBubbleTap') {
        setState(() => _captureOn = !_captureOn);
        final p = await SharedPreferences.getInstance();
        await p.setBool('cap', _captureOn);
        _pushState();
        _toast(_captureOn ? 'Capture ON — SS will be captured' : 'Capture OFF');
      } else if (call.method == 'onBubbleSelect') {
        final box = call.arguments as String;
        setState(() => _activeBox = box);
        await _saveCounts();
        _pushState();
        if (box == 'none') {
          _toast('NO BOX — SS will not be saved');
        } else {
          final m = _max[box] ?? 0;
          if (_countOf(box) >= m) {
            _toast('${box.toUpperCase()} FULL — select another box');
          } else {
            _toast('${box.toUpperCase()} select — auto-upload ON');
          }
        }
      } else if (call.method == 'onBubbleOk') {
        await _onOkay();
      }
    });
  }

  Future<Uint8List> _compress(Uint8List bytes, {int maxKB = 1024}) async {
    try {
      final r = await _galleryChannel.invokeMethod<Uint8List>('compress', {'bytes': bytes, 'maxKB': maxKB});
      if (r != null && r.isNotEmpty) return r;
    } catch (e) {}
    return _downscale(bytes);
  }

  Future<Uint8List> _downscale(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      const maxDim = 1600;
      if (src.width <= maxDim && src.height <= maxDim) {
        final out = await src.toByteData(format: ui.ImageByteFormat.png);
        src.dispose();
        codec.dispose();
        return out!.buffer.asUint8List();
      }
      final scale = maxDim / math.max(src.width, src.height);
      final w = (src.width * scale).round();
      final h = (src.height * scale).round();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
          src,
          Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint());
      final pic = recorder.endRecording();
      final outImg = await pic.toImage(w, h);
      final data = await outImg.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      codec.dispose();
      outImg.dispose();
      pic.dispose();
      return data!.buffer.asUint8List();
    } catch (e) {
      return bytes;
    }
  }

  Future<int> _inject(String box, String b64, String name) async {
    try {
      final r = await _controller.runJavaScriptReturningResult(_injectJs(box, b64, name));
      final s = r.toString().replaceAll('"', '');
      if (s.startsWith('ok:')) return int.tryParse(s.substring(3)) ?? -1;
    } catch (e) {}
    return -1;
  }

  Future<bool> _sendOne(String box, String path) async {
    try {
      final raw = await File(path).readAsBytes();
      var bytes = await _compress(raw);
      final name = path.split('/').last;
      final expect = (box == 'corr') ? 1 : (_siteCount[box] ?? 0) + 1;
      int got = await _inject(box, base64Encode(bytes), name);
      if (got != expect) {
        bytes = await _compress(raw, maxKB: 300);
        got = await _inject(box, base64Encode(bytes), name);
      }
      if (got > 0) {
        _siteCount[box] = got;
        setState(() {
          _queue.remove('$box|$path');
          _deliveredOk.add(path);
          _deliveredBox[path] = box;
        });
        await _saveCounts();
        return true;
      }
    } catch (e) {}
    return false;
  }

  Future<void> _flush() async {
    if (_flushing || !_fg || _queue.isEmpty) return;
    _flushing = true;
    final snapshot = List<String>.from(_queue);
    for (final it in snapshot) {
      final sep = it.indexOf('|');
      if (sep < 0) continue;
      final box = it.substring(0, sep);
      final path = it.substring(sep + 1);
      final ok = await _sendOne(box, path);
      if (!ok) {
        _toast('Upload pending — will retry');
        break;
      }
    }
    _flushing = false;
  }

  Future<void> _onOkay() async {
    await Future.delayed(const Duration(milliseconds: 800));
    await _flush();
    if (_deliveredOk.isEmpty) {
      _toast('No new deliveries');
    } else {
      final List<String> toDel = List<String>.from(_deliveredOk);
      final Set<String> boxes = _deliveredBox.values.toSet();
      _deliveredOk.clear();
      _deliveredBox.clear();
      bool deleted = false;
      if (_autoDelete) {
        try {
          final r = await _galleryChannel.invokeMethod<int>('deleteFiles', {'paths': toDel});
          deleted = (r ?? 0) == 1;
        } catch (e) {}
      }
      if (deleted) {
        setState(() {
          for (final b in boxes) {
            if (b == 'htf') { _cHtf = 0; } 
            else if (b == 'entry') { _cEntry = 0; } 
            else if (b == 'corr') { _cCorr = 0; }
            _siteCount[b] = 0;
          }
        });
        await _saveCounts();
        _overlayShown = false;
        final p = await SharedPreferences.getInstance();
        await p.setBool('bubble', false);
        try {
          await _galleryChannel.invokeMethod('hideBubble');
        } catch (e) {}
        _toast('Delivered + deleted — bubble OFF');
        for (final b in boxes) {
          try {
            await _controller.runJavaScript('if(window.__ak){window.__ak["$b"]=[];}');
          } catch (e) {}
        }
      }
    }
    await _controller.runJavaScript('''(function(){
      var els = document.querySelectorAll('nav button, nav a, button, a, div[role="button"]');
      for (var i=0;i<els.length;i++){
        var t=(els[i].innerText||'').trim();
        if (t==='Analysis'){ els[i].click(); return 'ok'; }
      }
      return 'fail';
    })();''');
  }

  Future<void> _pickAndInject(String box) async {
    try {
      final res = await _galleryChannel.invokeMethod<List<Object?>>('pickFiles');
      final list = (res ?? []).map((e) => e.toString()).toList();
      if (list.isEmpty) {
        _toast('No SS selected');
        return;
      }
      int ok = 0;
      for (final path in list) {
        if (await _sendOne(box, path)) ok++;
      }
      if (ok > 0) {
        _toast('$ok SS in ${box.toUpperCase()} ✅');
      } else {
        _toast('Could not add to box ❌');
      }
    } catch (e) {
      _toast('Picker unavailable ❌');
    }
  }

  String _injectJs(String box, String b64, String name) {
    return '''(function(){
      function classify(inp){
        var host = inp;
        for (var up=0; up<8 && host; up++){
          var txt = (host.innerText||'').toUpperCase();
          if (txt.length>0 && txt.length<400){
            if (txt.indexOf('CORRELATION')>=0 || txt.indexOf('DXY')>=0) return 'corr';
            if (txt.indexOf('ENTRY')>=0) return 'entry';
            if (txt.indexOf('HTF')>=0) return 'htf';
          }
          host = host.parentElement;
        }
        var inputs=document.querySelectorAll('input[type=file]');
        var idx = Array.prototype.indexOf.call(inputs, inp);
        if (idx===0) return 'entry';
        if (idx===1) return 'corr';
        if (idx===2) return 'htf';
        return inp.multiple ? 'htf' : 'corr';
      }
      function inputFor(b){
        var inputs=document.querySelectorAll('input[type=file]');
        for (var i=0;i<inputs.length;i++){ if (classify(inputs[i])===b) return inputs[i]; }
        if (b==='corr'){ for (var j=0;j<inputs.length;j++){ if(!inputs[j].multiple) return inputs[j]; } }
        if (b==='entry' && inputs.length) return inputs[0];
        if (b==='htf'){ for (var k=0;k<inputs.length;k++){ if(inputs[k].multiple) return inputs[k]; } }
        return null;
      }
      var inp=inputFor('$box');
      if(!inp) return 'fail';
      window.__ak = window.__ak || {};
      var list = window.__ak['$box'];
      if (!list) {
        list = [];
        if (inp.files) { for (var e2=0; e2<inp.files.length; e2++) list.push(inp.files[e2]); }
        window.__ak['$box'] = list;
      }
      var bin=atob('$b64'); var arr=new Uint8Array(bin.length);
      for (var i=0;i<bin.length;i++) arr[i]=bin.charCodeAt(i);
      list.push(new File([arr],'$name',{type:'image/jpeg'}));
      var dt=new DataTransfer();
      for (var q2=0; q2<list.length; q2++) dt.items.add(list[q2]);
      inp.files=dt.files; inp.dispatchEvent(new Event('change',{bubbles:true}));
      return 'ok:'+inp.files.length;
    })();''';
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
            if (b == 'htf') { _cHtf = 0; _siteCount['htf'] = 0; } 
            else if (b == 'entry') { _cEntry = 0; _siteCount['entry'] = 0; } 
            else { _cCorr = 0; _siteCount['corr'] = 0; }
            _queue.removeWhere((q) => q.startsWith('$b|'));
            _deliveredOk.removeWhere((p) => _deliveredBox[p] == b);
            _deliveredBox.removeWhere((k, v) => v == b);
          });
          _saveCounts();
          _pushState();
          try {
            await _controller.runJavaScript('if(window.__ak){window.__ak["$b"]=[];}');
          } catch (e) {}
        } else if (m.startsWith('PICK:')) {
          await _pickAndInject(m.substring(5));
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          _progressN.value = p / 100;
        },
        onPageStarted: (_) {
          _progressN.value = 0;
          if (_firstLoad) setState(() => _isLoading = true);
        },
        onPageFinished: (_) async {
          setState(() {
            _isLoading = false;
            _firstLoad = false;
            _cHtf = 0;
            _cEntry = 0;
            _cCorr = 0;
            _siteCount['htf'] = 0;
            _siteCount['entry'] = 0;
            _siteCount['corr'] = 0;
          });
          _progressN.value = 1;
          await _saveCounts();
          _pushState();
          await _controller.runJavaScript(_pageHookJs());
          _flush();
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  String _pageHookJs() {
    return '''(function(){
      if (window.__aniketHook) return;
      window.__aniketHook = true;
      var st = document.createElement('style');
      st.innerHTML = '#netlify-badge, .netlify-badge, [id*="netlify" i], [class*="netlify" i], a[href*="netlify.com"], a[href*="netlify.app"] { display:none !important; visibility:hidden !important; opacity:0 !important; pointer-events:none !important; }';
      document.documentElement.appendChild(st);
      function lightClean(){
        var b = document.querySelector('#netlify-badge, .netlify-badge, [id*="netlify" i], [class*="netlify" i], a[href*="netlify.com"], a[href*="netlify.app"]');
        if (b) { b.remove(); }
      }
      lightClean();
      setInterval(lightClean, 2000);
      function classify(inp){
        var host = inp;
        for (var up=0; up<8 && host; up++){
          var txt = (host.innerText||'').toUpperCase();
          if (txt.length>0 && txt.length<400){
            if (txt.indexOf('CORRELATION')>=0 || txt.indexOf('DXY')>=0) return 'corr';
            if (txt.indexOf('ENTRY')>=0) return 'entry';
            if (txt.indexOf('HTF')>=0) return 'htf';
          }
          host = host.parentElement;
        }
        var inputs=document.querySelectorAll('input[type=file]');
        var idx = Array.prototype.indexOf.call(inputs, inp);
        if (idx===0) return 'entry';
        if (idx===1) return 'corr';
        if (idx===2) return 'htf';
        return inp.multiple ? 'htf' : 'corr';
      }
      document.addEventListener('click', function(e){
        var t = e.target;
        var inp = null;
        if (t && t.tagName === 'INPUT' && t.type === 'file') inp = t;
        if (!inp && t && t.closest) {
          var lab = t.closest('label');
          if (lab) {
            var forId = lab.getAttribute('for');
            if (forId) { var el2 = document.getElementById(forId); if (el2 && el2.type === 'file') inp = el2; }
            if (!inp) { var el3 = lab.querySelector('input[type=file]'); if (el3) inp = el3; }
          }
        }
        if (inp) {
          e.preventDefault();
          e.stopPropagation();
          FlutterBridge.postMessage('PICK:' + classify(inp));
          return;
        }
        var b = e.target.closest ? e.target.closest('button') : null;
        if(!b) return;
        var t2=(b.innerText||'').toUpperCase();
        if (t2.indexOf('HTF')>=0) FlutterBridge.postMessage('CLEARED:htf');
        else if (t2.indexOf('CORRELATION')>=0) FlutterBridge.postMessage('CLEARED:corr');
        else if (t2.indexOf('ENTRY')>=0) FlutterBridge.postMessage('CLEARED:entry');
      }, true);
    })();''';
  }

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
    final p = await SharedPreferences.getInstance();
    await p.setBool('bubble', _overlayShown);
    setState(() {});
  }

  void _snack(String t) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading && _firstLoad)
              Container(color: kBg, child: const Center(child: CircularProgressIndicator(color: kGold))),
            ValueListenableBuilder<double>(
              valueListenable: _progressN,
              builder: (context, v, _) {
                if (_firstLoad || v >= 1) return const SizedBox.shrink();
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(value: v, minHeight: 3, color: kGold, backgroundColor: Colors.transparent),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showSettings(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings, color: kGold, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          _sheetRefresh = () => setModal(() {});
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App Settings', style: TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('Active: ${_activeBox == 'none' ? 'NO BOX' : _activeBox.toUpperCase()}  •  HTF $_cHtf/6 • ENTRY $_cEntry/4 • CORR $_cCorr/1  •  Queue: ${_queue.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Floating Bubble', style: TextStyle(color: Colors.white)),
                  value: _overlayShown,
                  activeColor: kGold,
                  onChanged: (_) async { await _toggleOverlay(); setModal(() {}); },
                ),
                SwitchListTile(
                  title: const Text('Capture ON (SS capture)', style: TextStyle(color: Colors.white)),
                  value: _captureOn,
                  activeColor: kGold,
                  onChanged: (v) async {
                    setState(() => _captureOn = v);
                    final p = await SharedPreferences.getInstance();
                    await p.setBool('cap', v);
                    _pushState();
                    setModal(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Gallery Auto-Delete', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('After OKAY, tap Allow in system dialog to delete', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _autoDelete,
                  activeColor: kGold,
                  onChanged: (v) async {
                    setState(() => _autoDelete = v);
                    final p = await SharedPreferences.getInstance();
                    await p.setBool('ad', v);
                    setModal(() {});
                  },
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _flush();
                    _toast('Queue: ${_queue.length} left');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: kGold),
                  child: const Text('Force Upload Now', style: TextStyle(color: Colors.black)),
                ),
                if (_owner) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerPanelScreen()));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                    child: const Text('Owner Panel', style: TextStyle(color: kGold)),
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }
}
