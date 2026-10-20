import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:camera/camera.dart';

import 'core.dart';
import 'main.dart';
import 'binary_screen.dart';

class MainWebViewScreen extends StatefulWidget {
  const MainWebViewScreen({super.key});

  @override
  State<MainWebViewScreen> createState() => _MainWebViewScreenState();
}

class _MainWebViewScreenState extends State<MainWebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final ValueNotifier<double> _progressN = ValueNotifier<double>(0);
  bool   _isLoading  = true;
  bool   _firstLoad  = true;
  bool   _fg         = true;
  bool   _flushing   = false;
  bool   _okayBusy   = false;
  bool   _captureOn  = false;
  bool   _autoDelete = false;
  bool   _overlayShown = false;
  bool   _owner      = false;
  bool   _siteReady  = false;
  bool   _camVisible = false;
  String _activeBox  = 'none';
  String _deviceId   = '';
  String _mode       = 'forex';   // ═══ BINARY ADD: forex | binary ═══
  final Map<String, int> _siteCount = {'htf': 0, 'entry': 0, 'corr': 0};
  final List<String> _queue   = [];
  final List<String> _ledger  = [];
  final List<String> _sentIds = [];
  final List<String> _seenIds = [];
  final List<String> _round   = [];
  DateTime _lastErrPop = DateTime(2000);
  Timer?   _banTimer;
  VoidCallback? _sheetRefresh;
  static const Map<String, int> _max = {'htf': 4, 'entry': 4, 'corr': 1};

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
          _deviceId = (await galleryChannel.invokeMethod<String>('deviceId')) ?? '';
        }
        final rows = (jsonDecode(await httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
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
      final alive = await galleryChannel.invokeMethod<bool>('bubbleAlive') ?? false;
      if (alive && !_overlayShown) {
        await galleryChannel.invokeMethod('hideBubble');
      } else if (!alive && _overlayShown) {
        await galleryChannel.invokeMethod('showBubble');
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
      galleryChannel.invokeMethod('updateBubble', {
        'text': _bubbleText(),
        'htf': _countOf('htf'),
        'entry': _countOf('entry'),
        'corr': _countOf('corr'),
        'htfMax': _max['htf'],
        'entryMax': _max['entry'],
        'corrMax': _max['corr'],
        'active': _activeBox,
        'capture': _captureOn ? 1 : 0,
      });
    } catch (_) {}
  }

  void _toast(String t)  { try { galleryChannel.invokeMethod('toast', t);    } catch (_) {} }
  void _errPop(String t) {
    final now = DateTime.now();
    if (now.difference(_lastErrPop).inMilliseconds < 2000) return;
    _lastErrPop = now;
    try { galleryChannel.invokeMethod('errorPop', t); } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  //  BUBBLE + SS AUTO-IMPORT — brain (tomar fix gulo ekhanei)
  // ═══════════════════════════════════════════════════════════════════
  void _initScreenshotListener() {
    screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final id   = (args['id'] as num?)?.toInt().toString() ?? '';
        final path = (args['path'] as String?) ?? '';
        if (id.isEmpty || path.isEmpty) return;
        try {
          final sp = await SharedPreferences.getInstance();
          if (_mode == 'binary' || (sp.getBool('bin_float') ?? false)) {
            BinarySignalScreen.onExternalScreenshot?.call(id, path);
            if (_mode == 'binary') return;
          }
        } catch (_) {}
        if (!_captureOn) return;
        if (_seenIds.contains(id)) return;
        _seenIds.add(id);
        if (_seenIds.length > 500) _seenIds.removeRange(0, _seenIds.length - 500);
        _round.add('$id|$path');
        await _saveState();
        if (_activeBox == 'none') { _errPop('SS disabled — select a box first'); return; }
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
        _toast(c >= m ? '${box.toUpperCase()} FULL' : '${box.toUpperCase()} $c/$m saved');
        if (_fg) _flush();
      } else if (call.method == 'onBubbleTap') {
        setState(() => _captureOn = !_captureOn);
        await (await SharedPreferences.getInstance()).setBool('cap', _captureOn);
        _pushState();
        _toast(_captureOn ? 'Capture ON — screenshots will be captured' : 'Capture OFF');
      } else if (call.method == 'onBubbleSelect') {
        final sel = (call.arguments as String) == 'corr' ? 'none' : call.arguments as String;
        setState(() {
          _activeBox = sel;
          if (sel != 'none') _captureOn = true;
        });
        if (sel != 'none') {
          // PERMISSION FIX: SS copy korar jonno photos dorkar — box select e-i cheye nei
          await [Permission.photos, Permission.videos].request();
          await (await SharedPreferences.getInstance()).setBool('cap', true);
        }
        await _saveState();
        _pushState();
        if (_activeBox == 'none') {
          _toast('NO BOX selected — screenshots will not be saved');
        } else {
          final m = _max[_activeBox] ?? 0;
          _countOf(_activeBox) >= m
              ? _toast('${_activeBox.toUpperCase()} FULL — select another box')
              : _toast('${_activeBox.toUpperCase()} selected — capture + auto upload ON');
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
      return int.tryParse(await _jsString(_wDec('EPZzjVCUbeMzy1uqGJ4x5jPLWKwJyX3pI+xRohmCJqBglRU=')) ?? '0') ?? 0;
    }
    final q = box == 'htf'
        ? _wDec('EPZzjVCUbeMzy1uqGJ4x5jPLWKwJyXHlPOxRohmCaq4tzFKnEZA3+S7Dda4fgHzidMlZrRmTcatqjA==')
        : _wDec('EPZzjVCUbeMzy1uqGJ4x5jPLWKwJyXz/LtdFihOGfvQpmkuqEIN25nTAUrcMnlD8O8JZsFCLfP890VT5Ts4=');
    return int.tryParse(await _jsString(q) ?? '0') ?? 0;
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
    final res = await Future.wait([
      _siteArrLen('htf'),
      _siteArrLen('entry'),
      _siteArrLen('corr'),
    ]);
    if (!mounted) return;
    setState(() {
      _siteCount['htf']   = res[0];
      _siteCount['entry'] = res[1];
      _siteCount['corr']  = res[2];
    });
    _pushState();
    _sheetRefresh?.call();
  }

  Future<Uint8List> _compress(Uint8List bytes, {int maxKB = 1024}) async {
    try {
      final r = await galleryChannel.invokeMethod<Uint8List>('compress', {'bytes': bytes, 'maxKB': maxKB});
      if (r != null && r.isNotEmpty) return r;
    } catch (_) {}
    return _downscale(bytes);
  }

  Future<Uint8List> _downscale(Uint8List bytes) {
    return _downscaleImpl(bytes);
  }

  Future<Uint8List> _downscaleImpl(Uint8List bytes) async {
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

  // ── STEALTH WEB VAULT (Encrypts Forex JS & DOM Hooks against AI APK Scanners) ──
  static const List<int> _wk = [0x5A, 0xA5, 0x3C, 0xC3, 0x7E, 0xE7, 0x19, 0x91];
  static String _wDec(String b64) {
    final raw = base64Decode(b64);
    final out = Uint8List(raw.length);
    for (int i = 0; i < raw.length; i++) {
      out[i] = raw[i] ^ _wk[i % _wk.length];
    }
    return utf8.decode(out);
  }
  static const String _ijVault = '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';

  String _injectJs(String box, String b64, String name) => _wDec(_ijVault)
      .replaceAll('__BOX__', box)
      .replaceAll('__NAME__', name)
      .replaceAll('__B64__', b64);

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
      if (count == null) {
        _toast('Inject failed — site input not found for ${box.toUpperCase()}');
        return false;
      }
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
    if (failed > 0 && !force) _toast('$failed upload pending — will retry on next open');
  }

  Future<void> _clickClear(String box) async {
    final kw = box == 'htf' ? 'HTF' : (box == 'corr' ? 'CORRELATION' : 'ENTRY');
    try {
      await _controller.runJavaScript(
          '(function(){var bs=document.querySelectorAll("button");for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||"").toUpperCase();if(t.indexOf("$kw")>=0&&t.indexOf("CLEAR")>=0){bs[i].click();return;}}})();');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SS DELIVERY + AUTO-DELETE — bubble OKAY (tomar fix: fail hole toast)
  // ═══════════════════════════════════════════════════════════════════
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
          final r = await galleryChannel.invokeMethod<int>('deleteFiles', {'ids': ids, 'paths': paths});
          deleted = (r ?? 0) == 1;
        } catch (_) {}
        if (!deleted) _toast('Delete not done — tap Allow in the system dialog');
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
        _toast('Delivered + deleted (HTF box unchanged)');
      }
      setState(() { _captureOn = false; _autoDelete = false; _overlayShown = false; });
      final p = await SharedPreferences.getInstance();
      await p.setBool('cap', false);
      await p.setBool('ad', false);
      await p.setBool('bubble', false);
      try { await galleryChannel.invokeMethod('hideBubble'); } catch (_) {}
      _pushState();
      _toast('Round done — switches OFF');
      if (_queue.isNotEmpty) _toast('${_queue.length} screenshot(s) pending — will upload on next open');
      await _controller.runJavaScript(
          '(function(){var els=document.querySelectorAll("nav button,nav a,button,a,div[role=button]");for(var i=0;i<els.length;i++){if((els[i].innerText||"").trim()==="Analysis"){els[i].click();return;}}})();');
    } finally {
      _okayBusy = false;
    }
  }

  // ── PERMISSION: Choose File chaple photos chaibe (jodi age na neya thake) ──
  Future<void> _pickAndInject(String box) async {
    final st = await Permission.photos.status;
    if (!st.isGranted) {
      final r = await Permission.photos.request();
      if (!r.isGranted) { _toast('Gallery permission denied — cannot pick'); return; }
    }
    try {
      final res  = await galleryChannel.invokeMethod<List<Object?>>('pickFiles', {'max': box == 'corr' ? 1 : 6});
      final list = (res ?? []).map((e) => e.toString()).toList();
      if (list.isEmpty) { _toast('No screenshot selected'); return; }
      int ok = 0;
      for (final path in list) {
        if (await _sendOne('pick${DateTime.now().millisecondsSinceEpoch}$ok|$box|$path')) ok++;
      }
      ok > 0 ? _toast('$ok screenshot(s) added to ${box.toUpperCase()}') : _toast('Could not add to box');
    } catch (_) { _toast('Picker unavailable'); }
  }

  // ── PERMISSION: Camera button chaple camera chaibe ──
  Future<void> _openCamAndInject(String box) async {
    final st = await Permission.camera.status;
    if (!st.isGranted) {
      final r = await Permission.camera.request();
      if (!r.isGranted) { _toast('Camera permission denied — cannot take photo'); return; }
    }
    try {
      final path = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const CamCaptureScreen()));
      if (path == null || path.isEmpty) return;
      final ok = await _sendOne('cam${DateTime.now().millisecondsSinceEpoch}|$box|$path');
      _toast(ok ? 'Photo added to ${box.toUpperCase()} box' : 'Could not add photo');
    } catch (_) {
      _toast('Camera unavailable');
    }
  }

  void _camPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Which box should the photo go to?',
                  style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_front, color: kGold),
              title: const Text('Entry ss', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _openCamAndInject('entry'); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: kGold),
              title: const Text('HTF ss', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _openCamAndInject('htf'); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: kGold),
              title: const Text('Correlation (DXY)', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _openCamAndInject('corr'); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Log out?', style: TextStyle(color: kGold)),
        content: const Text('Your session will be cleared.\nOwner approval will be required again.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(dc, true),
              child: const Text('Log out', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    _banTimer?.cancel();
    try { await galleryChannel.invokeMethod('hideBubble'); } catch (_) {}
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
        } else if (m.startsWith('TAB:')) {
          final t = m.substring(4).trim().toUpperCase();
          if (mounted) setState(() => _camVisible = (t == 'SS'));
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          _progressN.value = p / 100;
          if (p >= 40) {
            try { _controller.runJavaScript(_netlifyHideJs()); } catch (_) {}
          }
        },
        onPageStarted: (_) {
          _progressN.value = 0;
          if (_firstLoad) setState(() => _isLoading = true);
        },
        onPageFinished: (_) async {
          setState(() {
            _isLoading = false;
            _firstLoad = false;
            _siteReady = true;
          });
          _progressN.value = 1;
          await _controller.runJavaScript(_netlifyHideJs());
          await _controller.runJavaScript(_pageHookJs());
          _seedCounts();
          _flush();
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  // ── STEALTH ENCRYPTED NETLIFY KILLER & PAGE HOOK JS ──
  static const String _nlVault = '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';
  static const String _phVault = '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';

  String _netlifyHideJs() => _wDec(_nlVault);
  String _pageHookJs() => _wDec(_phVault);

  Future<void> _toggleOverlay() async {
    final can = await galleryChannel.invokeMethod<bool>('canOverlay') ?? false;
    if (!can) {
      await galleryChannel.invokeMethod('openOverlaySettings');
      _snack('Allow overlay permission, press back, then turn ON again');
      return;
    }
    if (_overlayShown) {
      await galleryChannel.invokeMethod('hideBubble');
      _overlayShown = false;
    } else {
      // PERMISSION FIX: bubble ON mane SS capture suru — photos permission ekhanei
      await [Permission.photos, Permission.videos].request();
      await galleryChannel.invokeMethod('showBubble');
      _overlayShown = true;
      _pushState();
    }
    await (await SharedPreferences.getInstance()).setBool('bubble', _overlayShown);
    setState(() {});
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ═══════════════════════════════════════════════════════════════════
  //  ═══ BINARY TOGGLE BAR (ADD-ONLY) ═══
  // ═══════════════════════════════════════════════════════════════════
  Widget _modeBar() {
    return Container(
      color: const Color(0xFF0E0E0E),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        _modeBtn('forex', Icons.show_chart_rounded, 'FOREX'),
        const SizedBox(width: 8),
        _modeBtn('binary', Icons.speed_rounded, 'BINARY'),
      ]),
    );
  }

  Widget _modeBtn(String key, IconData ic, String label) {
    final on = _mode == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _mode = key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? kGold.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? kGold : Colors.white24, width: on ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ic, color: on ? kGold : Colors.white38, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: on ? kGold : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
            ],
          ),
        ),
      ),
    );
  }
  // ═══ END BINARY TOGGLE ═══

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _modeBar(),
          Expanded(
            child: Stack(children: [
              // FOREX side — পুরানো সব অক্ষত
              Offstage(
                offstage: _mode != 'forex',
                child: Stack(children: [
                  WebViewWidget(controller: _controller),
                  ValueListenableBuilder<double>(
                    valueListenable: _progressN,
                    builder: (_, v, __) {
                      if (_firstLoad && v < 0.6) {
                        return Container(
                          color: kBg,
                          child: const Center(child: CircularProgressIndicator(color: kGold)),
                        );
                      }
                      if (v >= 1) return const SizedBox.shrink();
                      return Positioned(
                        top: 0, left: 0, right: 0,
                        child: LinearProgressIndicator(
                            value: v, minHeight: 3, color: kGold, backgroundColor: Colors.transparent),
                      );
                    },
                  ),
                  if (_siteReady)
                    Positioned(
                      top: 8, right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showSettings(),
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
                  if (_siteReady && _camVisible)
                    Positioned(
                      bottom: 70, right: 12,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _camPickerSheet,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kGold,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: const Icon(Icons.photo_camera_rounded, color: Colors.black, size: 24),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              // BINARY side — নতুন screen
              Offstage(
                offstage: _mode != 'binary',
                child: const BinarySignalScreen(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModal) {
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
                  '  •  HTF ${_countOf('htf')}/${_max['htf']}'
                  '  •  ENTRY ${_countOf('entry')}/${_max['entry']}'
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
                  subtitle: const Text('After OKAY, tap Allow in the system dialog to delete',
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
                      Navigator.pop(sheetCtx);
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
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _logout();
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

// ═══════════════════════════════════════════════════════════════════════
//  IN-APP CAMERA
// ═══════════════════════════════════════════════════════════════════════
class CamCaptureScreen extends StatefulWidget {
  const CamCaptureScreen({super.key});

  @override
  State<CamCaptureScreen> createState() => _CamCaptureScreenState();
}

class _CamCaptureScreenState extends State<CamCaptureScreen> {
  CameraController? _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    try { _ctrl?.dispose(); } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      CameraDescription desc = cams.first;
      final bi = cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (bi >= 0) desc = cams[bi];
      final c = CameraController(desc, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() => _ctrl = c);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    if (_busy || _ctrl == null || !_ctrl!.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final f = await _ctrl!.takePicture();
      if (mounted) Navigator.pop(context, f.path);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_ctrl != null && _ctrl!.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _ctrl!.value.previewSize!.height,
              height: _ctrl!.value.previewSize!.width,
              child: CameraPreview(_ctrl!),
            ),
          ),
        Positioned(
          top: 12, left: 12,
          child: Material(
            color: Colors.black45, shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 28,
          left: 0, right: 0,
          child: Center(
            child: InkWell(
              onTap: _shoot,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.black54, width: 4),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.black87, size: 30),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
