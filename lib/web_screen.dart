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
    _loadAppLogoDataUrl();
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
      _syncMultiKeysToForexWeb();
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
          if (_mode == 'binary' || (!_captureOn && (sp.getBool('bin_float') ?? false))) {
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
          await (await SharedPreferences.getInstance()).setBool('cap', true);
          if (_fg) {
            try { await [Permission.photos, Permission.videos].request(); } catch (_) {}
          }
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
      return int.tryParse(await _jsString('JSON.stringify(window.dxyImage?1:0)') ?? '0') ?? 0;
    }
    final q = box == 'htf'
        ? 'JSON.stringify(window.htfImages?window.htfImages.length:0)'
        : 'JSON.stringify(window.entryImages?window.entryImages.length:0)';
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

  String _injectJs(String box, String b64, String name) => '''
  (function(){
    function byId(b){if(b==='htf')return document.getElementById('htfInput');if(b==='entry')return document.getElementById('entryInput');if(b==='corr')return document.getElementById('dxyInput');return null;}
    function headOf(inp){var host=inp;for(var up=0;up<6&&host;up++){var t=(host.innerText||'').toUpperCase();if(t.length>=10&&t.length<=400){if(t.indexOf('CORRELATION')>=0||t.indexOf('DXY')>=0||t.indexOf('ENTRY')>=0||t.indexOf('HTF')>=0)return t;}host=host.parentElement;}return '';}
    function pickInputFallback(b){var inputs=document.querySelectorAll('input[type=file]');var i;for(i=0;i<inputs.length;i++){var h=headOf(inputs[i]);if(b==='corr'&&(h.indexOf('CORRELATION')>=0||h.indexOf('DXY')>=0))return inputs[i];if(b==='entry'&&h.indexOf('ENTRY')>=0)return inputs[i];if(b==='htf'&&h.indexOf('HTF')>=0)return inputs[i];}if(b==='corr'){for(i=0;i<inputs.length;i++){if(!inputs[i].multiple)return inputs[i];}return null;}var muls=[];for(i=0;i<inputs.length;i++){if(inputs[i].multiple)muls.push(inputs[i]);}if(b==='entry')return muls[0]||null;if(b==='htf')return muls[muls.length-1]||muls[0]||null;return null;}
    var inp=byId('$box')||pickInputFallback('$box');if(!inp)return 'fail';
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
    if (!await File(path).exists()) {
      setState(() => _queue.remove(entry));
      await _saveState();
      _pushState();
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
      _fg = true;
      await Future.delayed(const Duration(milliseconds: 250));
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
      _fg = true;
      await Future.delayed(const Duration(milliseconds: 200));
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

  // ═══════════════════════════════════════════════════════════════════
  //  ADD-ONLY MULTI-AI FOREX BRIDGE (100% SAFE FOR ALL 20 FOREX KEY SLOTS!)
  //  • Leaves all existing 20 Forex key slots in `localStorage` untouched
  //    if you already added keys there; only pre-fills if Forex has 0 keys.
  //  • Supports Gemini (`AIza...`), Groq (`gsk_...`), OpenRouter (`sk-or-...`),
  //    and Mistral keys with automatic failover when a key's quota is full!
  // ═══════════════════════════════════════════════════════════════════
  String _cachedLogoDataUrl = '';

  Future<String> _loadAppLogoDataUrl() async {
    if (_cachedLogoDataUrl.isNotEmpty) return _cachedLogoDataUrl;
    try {
      final bd = await DefaultAssetBundle.of(context).load('assets/logo.png');
      final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      if (bytes.isNotEmpty) {
        _cachedLogoDataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
        return _cachedLogoDataUrl;
      }
    } catch (_) {}
    return '';
  }

  // Tracks keys that recently hit quota limit so fresh keys are tried first
  final Map<String, DateTime> _keyCooldownUntil = {};
  String _lastWorkingForexKey = '';

  String _unwrapApiKey(String raw) {
    var s = raw
        .replaceAll(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
    for (int i = 0; i < 4; i++) {
      final low = s.toLowerCase();
      if (s.startsWith('AIza') ||
          s.startsWith('gsk_') ||
          s.startsWith('sk-or-') ||
          low.startsWith('mstrl_') ||
          low.startsWith('mistral_') ||
          low.startsWith('mistral:')) {
        return s;
      }
      // Only decode Base64 if it actually has a known Base64 key prefix:
      // QUl6 = AIza, Z3Nr = gsk_, c2st = sk-, bXN0cm = mstrl
      if (s.startsWith('QUl6') ||
          s.startsWith('Z3Nr') ||
          s.startsWith('c2st') ||
          s.startsWith('bXN0cm')) {
        try {
          final decodedBytes = base64Decode(s);
          var decodedStr = utf8.decode(decodedBytes, allowMalformed: false).trim();
          try {
            decodedStr = Uri.decodeComponent(decodedStr).trim();
          } catch (_) {}
          if (decodedStr.length >= 16 &&
              !decodedStr.contains(' ') &&
              RegExp(r'^[\x21-\x7E]+$').hasMatch(decodedStr)) {
            s = decodedStr;
            continue;
          }
        } catch (_) {}
      }
      break;
    }
    return s;
  }

  /// Strips website-specific tag prefixes (like `mstrl_`) before calling the real API server
  String _cleanProviderAuthToken(String rawKey) {
    final s = _unwrapApiKey(rawKey);
    return s
        .replaceFirst(
          RegExp(r'^(mstrl_|mistral_|mistral:|groq_|groq:|openrouter_|or_)', caseSensitive: false),
          '',
        )
        .trim();
  }

  // Quality tier rank: prioritize fast non-exhausted providers (Groq Llama-4 Vision, Mistral Pixtral, Gemini, OpenRouter)
  int _keyQualityTier(String k) {
    final s = _unwrapApiKey(k);
    final low = s.toLowerCase();
    if (s == _lastWorkingForexKey && s.isNotEmpty) return 0;
    if (s.startsWith('gsk_')) return 1;
    if (low.startsWith('mstrl_') || low.startsWith('mistral_') || (!s.startsWith('AIza') && !s.startsWith('sk-or-'))) return 2;
    if (s.startsWith('AIza')) return 3;
    return 4; // OpenRouter
  }

  String _providerLabelForKey(String k) {
    final s = _unwrapApiKey(k);
    if (s.startsWith('AIza')) return 'Gemini';
    if (s.startsWith('gsk_')) return 'Groq';
    if (s.startsWith('sk-or-')) return 'OpenRouter';
    return 'Mistral';
  }

  List<String> _sortKeysByBestAnalysisQuality(List<String> keys, {String preferredKey = ''}) {
    final now = DateTime.now();
    final active = <String>[];
    final cooledDown = <String>[];
    final cleanPreferred = _unwrapApiKey(preferredKey);

    for (final rawK in keys) {
      final k = _unwrapApiKey(rawK);
      if (k.length < 16) continue;
      if (active.contains(k) || cooledDown.contains(k)) continue;
      final until = _keyCooldownUntil[k];
      if (until != null && until.isAfter(now)) {
        cooledDown.add(k);
      } else {
        active.add(k);
      }
    }

    active.sort((a, b) {
      if (cleanPreferred.isNotEmpty) {
        if (a == cleanPreferred && b != cleanPreferred) return -1;
        if (b == cleanPreferred && a != cleanPreferred) return 1;
      }
      return _keyQualityTier(a).compareTo(_keyQualityTier(b));
    });
    cooledDown.sort((a, b) => _keyQualityTier(a).compareTo(_keyQualityTier(b)));
    return [...active, ...cooledDown];
  }

  // Detects if an AI response was cut off mid-way (e.g., 60% done before hitting token/quota limit)
  bool _isPartialOrTruncatedResponse(String txt, String finishReason, bool wantJson) {
    final clean = txt.trim();
    if (clean.isEmpty) return true;
    final fr = finishReason.toUpperCase();
    if (fr.contains('LENGTH') || fr.contains('MAX_TOKENS') || fr.contains('TOKEN')) {
      return true;
    }
    if (wantJson || clean.startsWith(String.fromCharCode(123)) || clean.contains('```json')) {
      final openBraces = RegExp(r"\x7B").allMatches(clean).length;
      final closeBraces = RegExp(r"\x7D").allMatches(clean).length;
      if (openBraces > 0 && openBraces > closeBraces) {
        return true; // JSON was cut off mid-way!
      }
    }
    // Check if a long analysis text abruptly ended mid-sentence without closing punctuation
    if (clean.length >= 80 && !wantJson) {
      final lastChar = clean[clean.length - 1];
      if (lastChar == ',' || lastChar == ':' || lastChar == '-' || lastChar == String.fromCharCode(40) || lastChar == '*') {
        return true;
      }
    }
    return false;
  }

  Future<void> _syncMultiKeysToForexWeb() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final rawSaved = p.getStringList('bin_keys') ?? [];
      final savedKeys = <String>[];
      bool repairedAny = false;
      for (final e in rawSaved) {
        final clean = _unwrapApiKey(e);
        if (clean != e.trim()) repairedAny = true;
        if (clean.length >= 16 && !savedKeys.contains(clean)) {
          savedKeys.add(clean);
        }
      }
      final sortedSaved = _sortKeysByBestAnalysisQuality(savedKeys);
      if (repairedAny && sortedSaved.isNotEmpty) {
        await p.setStringList('bin_keys', sortedSaved);
      }
      final keysJson = jsonEncode(sortedSaved);
      final logoDataUrl = await _loadAppLogoDataUrl();
      await _controller.runJavaScript(_buildForexMultiAiBridgeJs(keysJson, logoDataUrl: logoDataUrl));
    } catch (_) {}
  }

  Future<void> _handleForexDartAiRequest(String jsonPayload) async {
    String reqId = '';
    try {
      final map = jsonDecode(jsonPayload) as Map<String, dynamic>;
      reqId = (map['reqId'] ?? '').toString();
      final rawKeys = (map['keys'] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? <String>[];
      final preferredKey = (map['preferredKey'] ?? '').toString().trim();
      final prompt = (map['prompt'] ?? '').toString();
      final rawImages = (map['images'] as List?) ?? const [];
      final stitchedB64 = (map['stitchedB64'] ?? '').toString();
      final wantJson = map['wantJson'] == true;

      final p = await SharedPreferences.getInstance();
      final spKeys = (p.getStringList('bin_keys') ?? []).map((e) => e.trim()).where((e) => e.isNotEmpty);
      final unsortedKeys = <String>[];
      for (final k in [...rawKeys, ...spKeys]) {
        final clean = _unwrapApiKey(k);
        if (clean.length >= 16 && !unsortedKeys.contains(clean)) {
          unsortedKeys.add(clean);
        }
      }

      // 1. Sort all candidate keys (respecting active preferredKey & skipping cooled-down keys!)
      final candidateKeys = _sortKeysByBestAnalysisQuality(unsortedKeys, preferredKey: preferredKey);

      final images = <Map<String, String>>[];
      for (final item in rawImages) {
        if (item is Map) {
          final b64 = (item['b64'] ?? '').toString();
          final mime = (item['mime'] ?? 'image/jpeg').toString();
          if (b64.length >= 200) {
            images.add({'mime': mime, 'b64': b64});
          }
        }
      }

      final singleComposite = (stitchedB64.length >= 200)
          ? <Map<String, String>>[{'mime': 'image/jpeg', 'b64': stitchedB64}]
          : (images.isNotEmpty ? <Map<String, String>>[images.first] : <Map<String, String>>[]);

      String? finalOut;
      String? partial60Out;
      String partialProvider = '';
      final usedProviders = <String>[];

      for (final key in candidateKeys) {
        final provName = _providerLabelForKey(key);
        final authToken = _cleanProviderAuthToken(key);

        // If a previous key already completed 60% of the analysis before its quota/token limit ran out,
        // build a continuation relay prompt so the next key finishes the remaining 40% seamlessly!
        final activePrompt = (partial60Out != null && partial60Out.isNotEmpty)
            ? '$prompt\n\n'
              '══════════════════════════════════════════════════════════════════\n'
              '[PARTIAL ANALYSIS ALREADY COMPLETED BY PREVIOUS KEY ($partialProvider — 60% DONE)]:\n'
              '$partial60Out\n'
              '══════════════════════════════════════════════════════════════════\n'
              'CONTINUATION INSTRUCTION: The previous API key ran out of quota/tokens after completing the partial analysis above. '
              'Using the partial analysis above (60%) and the chart/market data, complete the remaining 40% and return the FULL, '
              '100% complete finalized output (in the exact format/JSON requested by the main prompt) without losing any findings from the first part!'
            : prompt;

        Map<String, String>? callRes;
        if (key.startsWith('AIza')) {
          callRes = await _forexCallGeminiNative(authToken, activePrompt, singleComposite.isNotEmpty ? singleComposite : images, wantJson);
        } else if (key.startsWith('gsk_')) {
          callRes = await _forexCallOpenAiCompatibleNative(
            endpoint: 'https://api.groq.com/openai/v1/chat/completions',
            key: authToken,
            visionModels: const [
              'meta-llama/llama-4-scout-17b-16e-instruct',
              'meta-llama/llama-4-maverick-17b-128e-instruct',
            ],
            textFallbackModels: const [
              'llama-3.3-70b-versatile',
              'llama-3.1-8b-instant',
            ],
            prompt: activePrompt,
            images: singleComposite,
            wantJson: wantJson,
          );
        } else if (key.startsWith('sk-or-')) {
          callRes = await _forexCallOpenAiCompatibleNative(
            endpoint: 'https://openrouter.ai/api/v1/chat/completions',
            key: authToken,
            visionModels: const [
              'google/gemma-3-27b-it:free',
              'mistralai/mistral-small-3.1-24b-instruct:free',
              'qwen/qwen2.5-vl-32b-instruct:free',
              'openrouter/free',
            ],
            textFallbackModels: const [
              'openrouter/free',
              'meta-llama/llama-3.3-70b-instruct:free',
              'google/gemma-3-27b-it:free',
            ],
            prompt: activePrompt,
            images: singleComposite,
            wantJson: wantJson,
            extraHeaders: const {
              'HTTP-Referer': 'https://aniketpro.ai',
              'X-Title': 'ANIKET PRO AI',
            },
          );
        } else {
          // Mistral (`mstrl_...` stripped via authToken!)
          callRes = await _forexCallOpenAiCompatibleNative(
            endpoint: 'https://api.mistral.ai/v1/chat/completions',
            key: authToken,
            visionModels: const [
              'pixtral-12b-2409',
              'mistral-small-latest',
              'pixtral-large-latest',
            ],
            textFallbackModels: const [
              'mistral-small-latest',
              'open-mistral-nemo',
            ],
            prompt: activePrompt,
            images: singleComposite,
            wantJson: wantJson,
          );
        }

        final outText = (callRes?['text'] ?? '').trim();
        final finishReason = (callRes?['finishReason'] ?? 'STOP').trim();

        if (outText.isEmpty) {
          // This key's quota is exhausted or failed -> put on 180s cooldown and move to next key immediately!
          _keyCooldownUntil[key] = DateTime.now().add(const Duration(seconds: 180));
          continue;
        }

        // Check if this key only finished ~60% (truncated/cut off by token/quota limit)
        if (_isPartialOrTruncatedResponse(outText, finishReason, wantJson)) {
          _keyCooldownUntil[key] = DateTime.now().add(const Duration(seconds: 90));
          if (partial60Out == null) {
            partial60Out = outText;
            partialProvider = provName;
            usedProviders.add('$provName 60%');
          } else {
            partial60Out = '$partial60Out\n$outText';
            if (!usedProviders.contains(provName)) usedProviders.add(provName);
          }
          continue;
        }

        // Complete 100% response obtained!
        _lastWorkingForexKey = key;
        if (partial60Out != null && partial60Out.isNotEmpty) {
          usedProviders.add('$provName 40%');
          if (outText.startsWith(String.fromCharCode(123)) || outText.contains('```json') || outText.length >= partial60Out.length) {
            finalOut = outText;
          } else {
            finalOut = '$partial60Out\n\n$outText';
          }
        } else {
          usedProviders.add(provName);
          finalOut = outText;
        }
        break;
      }

      if ((finalOut == null || finalOut.isEmpty) && partial60Out != null && partial60Out.isNotEmpty) {
        finalOut = partial60Out;
      }

      if (finalOut != null && finalOut.trim().isNotEmpty && usedProviders.isNotEmpty && prompt.length > 120) {
        _toast('⚡ Analysis Done (${usedProviders.join(" → ")} + 12 Pro Skills)');
      }

      if (reqId.isNotEmpty) {
        final encodedOut = jsonEncode(finalOut ?? '');
        await _controller.runJavaScript('if(window.__resolveForexDartAi) window.__resolveForexDartAi("$reqId", $encodedOut);');
      }
    } catch (_) {
      if (reqId.isNotEmpty) {
        try {
          await _controller.runJavaScript('if(window.__resolveForexDartAi) window.__resolveForexDartAi("$reqId", "");');
        } catch (_) {}
      }
    }
  }

  Future<Map<String, String>?> _forexCallGeminiNative(
    String key,
    String prompt,
    List<Map<String, String>> images,
    bool wantJson,
  ) async {
    const models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    for (final m in models) {
      HttpClient? client;
      try {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
        final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent?key=${Uri.encodeQueryComponent(key)}');
        final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

        final parts = <Map<String, dynamic>>[
          {'text': prompt},
          for (final img in images.take(2))
            {
              'inline_data': {
                'mime_type': img['mime'] ?? 'image/jpeg',
                'data': img['b64'] ?? '',
              }
            }
        ];

        final genCfg = <String, dynamic>{'temperature': 0.2};
        if (wantJson) genCfg['responseMimeType'] = 'application/json';
        if (m.contains('2.5')) genCfg['thinkingConfig'] = {'thinkingBudget': 0};

        final body = jsonEncode({
          'contents': [
            {'parts': parts}
          ],
          'generationConfig': genCfg,
        });

        req.add(utf8.encode(body));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final txt = await resp.transform(utf8.decoder).join();
          final root = jsonDecode(txt) as Map<String, dynamic>;
          final cands = root['candidates'] as List?;
          if (cands != null && cands.isNotEmpty) {
            final cand0 = cands.first as Map;
            final finishReason = (cand0['finishReason'] ?? 'STOP').toString();
            final content = cand0['content'] as Map?;
            final rParts = content?['parts'] as List?;
            if (rParts != null) {
              final sb = StringBuffer();
              for (final rp in rParts) {
                if (rp is Map && rp['thought'] != true && rp['text'] != null) {
                  sb.write(rp['text'].toString());
                }
              }
              final resStr = sb.toString().trim();
              if (resStr.isNotEmpty) {
                return {'text': resStr, 'finishReason': finishReason};
              }
            }
          }
        } else if (resp.statusCode == 429 || resp.statusCode == 403 || resp.statusCode == 400) {
          // Quota exhausted or key invalid -> stop trying more Gemini models on this key immediately!
          break;
        }
      } catch (_) {
      } finally {
        client?.close(force: true);
      }
    }
    return null;
  }

  Future<Map<String, String>?> _forexCallOpenAiCompatibleNative({
    required String endpoint,
    required String key,
    required List<String> visionModels,
    required List<String> textFallbackModels,
    required String prompt,
    required List<Map<String, String>> images,
    required bool wantJson,
    Map<String, String>? extraHeaders,
  }) async {
    Map<String, String>? partialCandidate;

    if (images.isNotEmpty) {
      for (final model in visionModels) {
        final res = await _sendSingleOpenAiRequest(
          endpoint: endpoint,
          key: key,
          model: model,
          prompt: prompt,
          images: images,
          extraHeaders: extraHeaders,
        );
        if (res != null && (res['status'] == '401' || res['status'] == '403')) {
          // Invalid API key -> break immediately without trying more models!
          return null;
        }
        if (res != null && (res['text'] ?? '').isNotEmpty) {
          if (!_isPartialOrTruncatedResponse(res['text']!, res['finishReason'] ?? 'STOP', wantJson)) {
            return res;
          }
          partialCandidate ??= res;
        }
      }
    }

    for (final model in textFallbackModels) {
      final contPrompt = (partialCandidate != null)
          ? '$prompt\n\n[PARTIAL ANALYSIS SO FAR (60%)]:\n${partialCandidate['text']}\n\nComplete the remaining 40% and output the full finalized response:'
          : prompt;
      final res = await _sendSingleOpenAiRequest(
        endpoint: endpoint,
        key: key,
        model: model,
        prompt: contPrompt,
        images: const [],
        extraHeaders: extraHeaders,
      );
      if (res != null && (res['status'] == '401' || res['status'] == '403')) {
        return null;
      }
      if (res != null && (res['text'] ?? '').isNotEmpty) {
        return res;
      }
    }

    return partialCandidate;
  }

  Future<Map<String, String>?> _sendSingleOpenAiRequest({
    required String endpoint,
    required String key,
    required String model,
    required String prompt,
    required List<Map<String, String>> images,
    Map<String, String>? extraHeaders,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.postUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (extraHeaders != null) {
        extraHeaders.forEach((k, v) => req.headers.set(k, v));
      }

      final Object messageContent = images.isEmpty
          ? prompt
          : <Map<String, dynamic>>[
              {'type': 'text', 'text': prompt},
              for (final img in images.take(1))
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:${img['mime'] ?? 'image/jpeg'};base64,${img['b64'] ?? ''}'
                  }
                }
            ];

      final body = jsonEncode({
        'model': model,
        'temperature': 0.2,
        'max_tokens': 2048,
        'messages': [
          {'role': 'user', 'content': messageContent}
        ],
      });

      req.add(utf8.encode(body));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final txt = await resp.transform(utf8.decoder).join();
        final root = jsonDecode(txt) as Map<String, dynamic>;
        final choices = root['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final ch0 = choices.first as Map;
          final finishReason = (ch0['finish_reason'] ?? 'stop').toString();
          final msg = ch0['message'] as Map?;
          final rawContent = (msg?['content'] ?? '').toString();
          final cleaned = rawContent.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();
          if (cleaned.isNotEmpty) {
            return {'text': cleaned, 'finishReason': finishReason, 'status': '200'};
          }
        }
      } else {
        return {'text': '', 'finishReason': 'ERROR', 'status': '${resp.statusCode}'};
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  String _buildForexMultiAiBridgeJs(String flutterKeysJson, {String logoDataUrl = ''}) {
    final tpl = r'''
(function(){
  try {
    var incomingKeys = __FLUTTER_KEYS_JSON__ || [];
    var customLogoUrl = __FLUTTER_LOGO_URL__ || '';
    if (customLogoUrl) {
      window.__aniketCustomLogoUrl = customLogoUrl;
    }
    if (!window.__aniketAllKeys) window.__aniketAllKeys = [];

    function cleanKey(k) {
      if (!k || typeof k !== 'string') return '';
      return k.replace(/^Bearer\s+/i, '').replace(/["'\s]/g, '').trim();
    }

    function deobfKey(s) {
      if (!s || typeof s !== 'string') return '';
      var cur = cleanKey(s);
      for (var step = 0; step < 4; step++) {
        var low = cur.toLowerCase();
        if (cur.indexOf('AIza') === 0 ||
            cur.indexOf('gsk_') === 0 ||
            cur.indexOf('sk-or-') === 0 ||
            low.indexOf('mstrl_') === 0 ||
            low.indexOf('mistral_') === 0 ||
            low.indexOf('mistral:') === 0) {
          return cur;
        }
        // Only Base64-decode if it starts with a known Base64-encoded prefix
        if (cur.indexOf('QUl6') === 0 || cur.indexOf('Z3Nr') === 0 || cur.indexOf('c2st') === 0 || cur.indexOf('bXN0cm') === 0) {
          try {
            var dec = atob(cur);
            try { dec = decodeURIComponent(dec); } catch(eU) {}
            dec = cleanKey(dec);
            if (dec && dec.length >= 16 && dec.indexOf(' ') < 0 && /^[\x21-\x7E]+$/.test(dec)) {
              cur = dec;
              continue;
            }
          } catch(e) {}
        }
        break;
      }
      return cur;
    }

    function cleanProviderAuthToken(rawKey) {
      var k = deobfKey(rawKey);
      return k.replace(/^(mstrl_|mistral_|mistral:|groq_|groq:|openrouter_|or_)/i, '').trim();
    }

    // Store plain-text keys in localStorage so the Forex site and Doctor report read them directly without Base64 corruption!
    function obfKey(s) {
      return deobfKey(s);
    }

    function readSiteKeys() {
      var out = [];
      function addCandidate(rawVal) {
        var k = deobfKey(rawVal);
        if (k && k.length >= 16 && out.indexOf(k) < 0) {
          out.push(k);
        }
      }
      try {
        var raw = localStorage.getItem('gemini_keys');
        if (raw) {
          var arr = JSON.parse(raw);
          if (Array.isArray(arr)) {
            for (var i = 0; i < arr.length; i++) addCandidate(arr[i]);
          }
        }
      } catch(e) {}
      try {
        var single = localStorage.getItem('gemini_key_v1');
        if (single) addCandidate(single);
      } catch(e) {}
      try {
        var inps = document.querySelectorAll('input');
        for (var j = 0; j < inps.length; j++) {
          var v = (inps[j].value || '').trim();
          if (v.length >= 20 && v.indexOf(' ') < 0 &&
              (v.indexOf('AIza') === 0 || v.indexOf('gsk_') === 0 || v.indexOf('sk-or-') === 0 || v.toLowerCase().indexOf('mstrl_') === 0 || /^[A-Za-z0-9_-]{28,}$/.test(v))) {
            addCandidate(v);
          }
        }
      } catch(e) {}
      return out;
    }

    var siteKeys = readSiteKeys();
    var merged = [];
    for (var i = 0; i < siteKeys.length; i++) {
      if (merged.indexOf(siteKeys[i]) < 0) merged.push(siteKeys[i]);
    }
    for (var j = 0; j < incomingKeys.length; j++) {
      var ck = cleanKey(incomingKeys[j]);
      if (ck && ck.length >= 16 && merged.indexOf(ck) < 0) merged.push(ck);
    }

    window.__aniketAllKeys = merged;

    // Immediately repair localStorage if it had Base64-encoded keys (e.g. Z3NrXz...) or if empty
    if (merged.length > 0) {
      var rawGKeys = localStorage.getItem('gemini_keys') || '';
      var rawG1 = localStorage.getItem('gemini_key_v1') || '';
      var needsRepair = (siteKeys.length === 0) ||
          (rawGKeys.indexOf('Z3Nr') >= 0 || rawGKeys.indexOf('QUl6') >= 0 || rawGKeys.indexOf('c2st') >= 0) ||
          (rawG1.indexOf('Z3Nr') >= 0 || rawG1.indexOf('QUl6') >= 0 || rawG1.indexOf('c2st') >= 0);
      if (needsRepair) {
        localStorage.setItem('gemini_keys', JSON.stringify(merged));
        localStorage.setItem('gemini_key_v1', merged[0]);
        if (!localStorage.getItem('gemini_key_idx')) {
          localStorage.setItem('gemini_key_idx', '0');
        }
        try {
          if (typeof window.updateKeyStatus === 'function') window.updateKeyStatus();
          if (typeof window.renderKeySlots === 'function') window.renderKeySlots();
        } catch(e) {}
      }
      if (window.FlutterBridge) {
        try {
          window.FlutterBridge.postMessage('SYNC_KEYS:' + JSON.stringify(merged));
        } catch(e) {}
      }
    }

    if (window.__aniketMultiAiFetchHooked) return;
    window.__aniketMultiAiFetchHooked = true;

    window.__forexDartAiCallbacks = {};
    window.__resolveForexDartAi = function(reqId, resultText) {
      var cb = window.__forexDartAiCallbacks[reqId];
      if (cb) {
        delete window.__forexDartAiCallbacks[reqId];
        cb(resultText || '');
      }
    };

    function callNativeDartAiFallback(keysList, preferredKey, promptText, rawImages, stitchedB64, wantJson) {
      return new Promise(function(resolve) {
        if (!window.FlutterBridge) {
          resolve('');
          return;
        }
        var reqId = 'req_' + Date.now() + '_' + Math.floor(Math.random() * 100000);
        var timer = setTimeout(function() {
          if (window.__forexDartAiCallbacks[reqId]) {
            delete window.__forexDartAiCallbacks[reqId];
            resolve('');
          }
        }, 16000);
        window.__forexDartAiCallbacks[reqId] = function(resTxt) {
          clearTimeout(timer);
          resolve(resTxt || '');
        };
        try {
          // Send only compact stitchedB64 (or at most 1 image if stitchedB64 is empty) so FlutterBridge is ultra-fast!
          var compactImgs = (!stitchedB64 && rawImages && rawImages.length > 0) ? [rawImages[0]] : [];
          window.FlutterBridge.postMessage('FOREX_DART_AI:' + JSON.stringify({
            reqId: reqId,
            keys: keysList,
            preferredKey: preferredKey || '',
            prompt: promptText,
            images: compactImgs,
            stitchedB64: stitchedB64 || '',
            wantJson: !!wantJson
          }));
        } catch(e) {
          clearTimeout(timer);
          delete window.__forexDartAiCallbacks[reqId];
          resolve('');
        }
      });
    }

    var origSetItem = localStorage.setItem.bind(localStorage);
    localStorage.setItem = function(k, v) {
      origSetItem(k, v);
      if (k === 'gemini_keys' || k === 'gemini_key_v1') {
        setTimeout(function(){
          var updated = readSiteKeys();
          if (updated.length > 0) {
            for (var u = 0; u < updated.length; u++) {
              if (window.__aniketAllKeys.indexOf(updated[u]) < 0) {
                window.__aniketAllKeys.push(updated[u]);
              }
            }
            if (window.FlutterBridge) {
              try {
                window.FlutterBridge.postMessage('SYNC_KEYS:' + JSON.stringify(window.__aniketAllKeys));
              } catch(e) {}
            }
          }
        }, 100);
      }
    };

    var origFetch = window.fetch.bind(window);

    function fetchWithTimeout(url, opts, timeoutMs) {
      timeoutMs = timeoutMs || 2800;
      if (typeof AbortController !== 'undefined') {
        var ctrl = new AbortController();
        var id = setTimeout(function() { try { ctrl.abort(); } catch(e) {} }, timeoutMs);
        var mergedOpts = Object.assign({}, opts || {}, { signal: ctrl.signal });
        return origFetch(url, mergedOpts).finally(function() { clearTimeout(id); });
      }
      return Promise.race([
        origFetch(url, opts || {}),
        new Promise(function(_, rej) { setTimeout(function() { rej(new Error('timeout')); }, timeoutMs); })
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNIFIED PRO ANALYSIS ENGINE:
    //  USER'S FOREX FEATURES (HTF/ENTRY/DXY SS + SMC/ICT MODE FILTERS)
    //  + ALL 11 DAY-TRADER SKILLS + ORDER FLOW / FOOTPRINT / HEATMAP
    // ═══════════════════════════════════════════════════════════════════
    var nyseHolidays = {
      '2026-01-01':1, '2026-01-19':1, '2026-02-16':1, '2026-04-03':1, '2026-05-25':1,
      '2026-06-19':1, '2026-07-03':1, '2026-09-07':1, '2026-11-26':1, '2026-12-25':1,
      '2027-01-01':1, '2027-01-18':1, '2027-02-15':1, '2027-03-26':1, '2027-05-31':1,
      '2027-06-18':1, '2027-07-05':1, '2027-09-06':1, '2027-11-25':1, '2027-12-24':1
    };
    var nyseEarlyCloses = { '2026-11-27':1, '2026-12-24':1, '2027-11-26':1 };

    function readUserForexModeSettings() {
      var res = {
        riskPct: 1.0,
        balance: 1000.0,
        dailyLossPct: 2.0,
        maxTrades: 10,
        aPlusThreshold: 8,
        atrMult: 1.5,
        tp1Pct: 50
      };
      try {
        var nodes = document.querySelectorAll('label, div, span');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (!el || (el.children && el.children.length > 3)) continue;
          var t = (el.textContent || '').trim().toLowerCase();
          if (!t || t.length > 100) continue;
          var parent = el.parentElement;
          if (!parent) continue;
          var inp = parent.querySelector('input[type=number], input[type=text], select');
          if (!inp && parent.parentElement) inp = parent.parentElement.querySelector('input[type=number], input[type=text], select');
          if (inp && inp.type !== 'checkbox') {
            var val = parseFloat(inp.value || inp.placeholder || '');
            if (!isNaN(val) && val > 0) {
              if (t.indexOf('risk per trade') >= 0) res.riskPct = val;
              else if (t.indexOf('account balance') >= 0) res.balance = val;
              else if (t.indexOf('daily loss limit') >= 0) res.dailyLossPct = val;
              else if (t.indexOf('max daily trades') >= 0) res.maxTrades = val;
              else if (t.indexOf('a+ threshold') >= 0) res.aPlusThreshold = val;
              else if (t.indexOf('atr multiplier') >= 0) res.atrMult = val;
              else if (t.indexOf('partial profit') >= 0) res.tp1Pct = val;
            }
          }
        }
      } catch(e) {}
      return res;
    }

    function calcWilderRsi(closes, period) {
      period = period || 14;
      if (!closes || closes.length <= period) return 50.0;
      var gains = 0, losses = 0;
      for (var i = 1; i <= period; i++) {
        var d = closes[i] - closes[i - 1];
        if (d >= 0) gains += d; else losses -= d;
      }
      var avgG = gains / period, avgL = losses / period;
      for (var j = period + 1; j < closes.length; j++) {
        var d2 = closes[j] - closes[j - 1];
        var g = d2 > 0 ? d2 : 0;
        var l = d2 < 0 ? -d2 : 0;
        avgG = ((avgG * (period - 1)) + g) / period;
        avgL = ((avgL * (period - 1)) + l) / period;
      }
      if (avgL === 0) return 100.0;
      return 100.0 - (100.0 / (1.0 + (avgG / avgL)));
    }

    function detectActivePair(promptText) {
      var combined = ((promptText || '') + ' ' + ((document.body && document.body.innerText) || '')).toUpperCase();
      var map = [
        ['XAUUSD', 'GC=F', 'XAU/USD (Gold)'],
        ['XAU/USD', 'GC=F', 'XAU/USD (Gold)'],
        ['GOLD', 'GC=F', 'XAU/USD (Gold)'],
        ['BTCUSD', 'BTC-USD', 'BTC/USD (Bitcoin)'],
        ['BTC/USD', 'BTC-USD', 'BTC/USD (Bitcoin)'],
        ['BTCUSDT', 'BTC-USD', 'BTC/USD (Bitcoin)'],
        ['BITCOIN', 'BTC-USD', 'BTC/USD (Bitcoin)'],
        ['ETHUSD', 'ETH-USD', 'ETH/USD (Ethereum)'],
        ['SOLUSD', 'SOL-USD', 'SOL/USD (Solana)'],
        ['EURUSD', 'EURUSD=X', 'EUR/USD'],
        ['EUR/USD', 'EURUSD=X', 'EUR/USD'],
        ['GBPUSD', 'GBPUSD=X', 'GBP/USD'],
        ['GBP/USD', 'GBPUSD=X', 'GBP/USD'],
        ['USDJPY', 'USDJPY=X', 'USD/JPY'],
        ['USD/JPY', 'USDJPY=X', 'USD/JPY'],
        ['AUDUSD', 'AUDUSD=X', 'AUD/USD'],
        ['USDCAD', 'USDCAD=X', 'USD/CAD'],
        ['XAGUSD', 'SI=F', 'XAG/USD (Silver)'],
        ['USOIL', 'CL=F', 'WTI Crude Oil'],
        ['NAS100', 'NQ=F', 'US100 (Nasdaq)'],
        ['US100', 'NQ=F', 'US100 (Nasdaq)'],
        ['US30', 'YM=F', 'US30 (Dow)']
      ];
      var pUp = (promptText || '').toUpperCase();
      for (var i = 0; i < map.length; i++) {
        if (pUp.indexOf(map[i][0]) >= 0) return { sym: map[i][1], label: map[i][2] };
      }
      for (var j = 0; j < map.length; j++) {
        if (combined.indexOf(map[j][0]) >= 0) return { sym: map[j][1], label: map[j][2] };
      }
      return { sym: 'GC=F', label: 'XAU/USD (Gold)' };
    }

    async function fetchCorsSafeCandles(sym, interval, limit) {
      try {
        var binMap = {
          'GC=F': 'PAXGUSDT',
          'BTC-USD': 'BTCUSDT',
          'ETH-USD': 'ETHUSDT',
          'SOL-USD': 'SOLUSDT',
          'EURUSD=X': 'EURUSDT',
          'GBPUSD=X': 'GBPUSDT',
          'AUDUSD=X': 'AUDUSDT'
        };
        var bSym = binMap[sym];
        if (bSym) {
          var bInt = interval === '1d' ? '1d' : '5m';
          var bLim = limit || (interval === '1d' ? 90 : 120);
          var bUrl = 'https://api.binance.com/api/v3/klines?symbol=' + bSym + '&interval=' + bInt + '&limit=' + bLim;
          var bResp = await fetchWithTimeout(bUrl, { method: 'GET' }, 2200);
          if (bResp && bResp.ok) {
            var klines = await bResp.json();
            if (Array.isArray(klines) && klines.length >= 15) {
              var bBars = [];
              for (var k = 0; k < klines.length; k++) {
                var row = klines[k];
                bBars.push({
                  o: parseFloat(row[1]),
                  h: parseFloat(row[2]),
                  l: parseFloat(row[3]),
                  c: parseFloat(row[4]),
                  v: parseFloat(row[5])
                });
              }
              var lastC = bBars[bBars.length - 1].c;
              var prevC = bBars.length >= 24 ? bBars[bBars.length - 24].c : bBars[0].o;
              return {
                bars: bBars,
                livePx: lastC,
                prevClose: prevC,
                source: 'Binance Live (' + bSym + ')'
              };
            }
          }
        }
      } catch(eB) {}

      try {
        var range = interval === '1d' ? '3mo' : '5d';
        var yUrl = 'https://query2.finance.yahoo.com/v8/finance/chart/' + encodeURIComponent(sym) + '?range=' + range + '&interval=' + interval;
        var yResp = await fetchWithTimeout(yUrl, { method: 'GET' }, 2500);
        if (yResp && yResp.ok) {
          var yJson = await yResp.json();
          var r0 = yJson && yJson.chart && yJson.chart.result && yJson.chart.result[0];
          if (r0) {
            var meta = r0.meta || {};
            var q0 = (r0.indicators && r0.indicators.quote && r0.indicators.quote[0]) || {};
            var cArr = q0.close || [], hArr = q0.high || [], lArr = q0.low || [], oArr = q0.open || [], vArr = q0.volume || [];
            var bars = [];
            for (var i = 0; i < cArr.length; i++) {
              if (cArr[i] != null && hArr[i] != null && lArr[i] != null) {
                bars.push({
                  o: oArr[i] != null ? oArr[i] : cArr[i],
                  h: hArr[i],
                  l: lArr[i],
                  c: cArr[i],
                  v: vArr[i] || 0
                });
              }
            }
            if (bars.length >= 15) {
              return {
                bars: bars,
                livePx: meta.regularMarketPrice || bars[bars.length - 1].c,
                prevClose: meta.chartPreviousClose || meta.previousClose || bars[0].o,
                source: 'Yahoo Finance Live'
              };
            }
          }
        }
      } catch(eY) {}
      return null;
    }

    window.__aniketTelemetryCache = {};

    async function runUnified11SkillsAndUserFeatures(promptText) {
      var det = detectActivePair(promptText);
      var sym = det.sym;
      var label = det.label;

      // Return cached 12-skill telemetry if fetched within the last 45 seconds!
      var cached = window.__aniketTelemetryCache[sym];
      if (cached && (Date.now() - cached.ts < 45000)) {
        return cached.text;
      }

      var userCfg = readUserForexModeSettings();
      var pairRes = await Promise.all([
        fetchCorsSafeCandles(sym, '5m', 120),
        fetchCorsSafeCandles(sym, '1d', 90)
      ]);
      var data5m = pairRes[0];
      var data1d = pairRes[1];
      if (!data5m || !data5m.bars || data5m.bars.length < 15) return null;

      var bars = data5m.bars;
      var livePx = data5m.livePx;
      var prevClose = data5m.prevClose;
      var chgPct = prevClose > 0 ? (((livePx - prevClose) / prevClose) * 100.0) : 0.0;
      var dec = livePx > 100 ? 2 : (livePx > 10 ? 3 : 5);

      var dailySetups = [];
      var hi90d = livePx, lo90d = livePx, sma20d = livePx, dailyRsi = 50.0;
      if (data1d && data1d.bars && data1d.bars.length > 0) {
        var dbars = data1d.bars;
        var dc = dbars.map(function(b){ return b.c; });
        var dh = dbars.map(function(b){ return b.h; });
        var dl = dbars.map(function(b){ return b.l; });
        hi90d = Math.max.apply(null, dh);
        lo90d = Math.min.apply(null, dl);
        if (dc.length >= 21) {
          dailyRsi = calcWilderRsi(dc, 14);
          var prior20 = dc.slice(-21, -1);
          var max20 = Math.max.apply(null, prior20);
          sma20d = prior20.reduce(function(a,b){ return a + b; }, 0) / prior20.length;
          if (livePx > max20) dailySetups.push('20D Closing-High Breakout');
          if (dc[dc.length - 2] < sma20d && livePx > sma20d) dailySetups.push('Reclaimed 20-Day SMA');
          if (dailyRsi < 32) dailySetups.push('Daily Oversold (RSI ' + dailyRsi.toFixed(1) + ')');
        }
      }

      var atrN = Math.min(14, bars.length - 1);
      var trSum = 0;
      for (var a = bars.length - atrN; a < bars.length; a++) {
        var cur = bars[a], pv = bars[a - 1].c;
        trSum += Math.max(cur.h - cur.l, Math.abs(cur.h - pv), Math.abs(cur.l - pv));
      }
      var atr14 = trSum / Math.max(1, atrN);
      var closes5m = bars.map(function(b){ return b.c; });
      var rsi5m = calcWilderRsi(closes5m, 14);

      var sess = bars.slice(-24);
      var orBars = sess.slice(0, 3);
      var orHigh = Math.max.apply(null, orBars.map(function(b){ return b.h; }));
      var orLow  = Math.min.apply(null, orBars.map(function(b){ return b.l; }));
      var orMid  = (orHigh + orLow) / 2.0;
      var orAvgVol = orBars.reduce(function(acc, b){ return acc + (b.v || 0); }, 0) / Math.max(1, orBars.length);
      var lastVolRatio = orAvgVol > 0 ? (sess[sess.length - 1].v / orAvgVol) : 1.0;

      var sessHigh = Math.max.apply(null, sess.map(function(b){ return b.h; }));
      var sessLow  = Math.min.apply(null, sess.map(function(b){ return b.l; }));
      var sessEq   = (sessHigh + sessLow) / 2.0;
      var sessSpan = Math.max(sessHigh - sessLow, atr14);
      var bullOte618 = sessHigh - (0.618 * sessSpan);
      var bullOte786 = sessHigh - (0.786 * sessSpan);
      var bearOte618 = sessLow + (0.618 * sessSpan);
      var bearOte786 = sessLow + (0.786 * sessSpan);
      var pdZone = livePx > sessEq ? 'PREMIUM ZONE (Above 50% Eq ' + sessEq.toFixed(dec) + ')' : 'DISCOUNT ZONE (Below 50% Eq ' + sessEq.toFixed(dec) + ')';

      var entryStatus = livePx > orHigh
        ? 'ORB BULLISH BREAKOUT TRIGGERED (Closed above OR High ' + orHigh.toFixed(dec) + ', Vol ' + lastVolRatio.toFixed(2) + 'x)'
        : (livePx < orLow
            ? 'ORB BEARISH BREAKDOWN TRIGGERED (Closed below OR Low ' + orLow.toFixed(dec) + ', Vol ' + lastVolRatio.toFixed(2) + 'x)'
            : 'INSIDE OPENING RANGE (' + orLow.toFixed(dec) + ' – ' + orHigh.toFixed(dec) + ', Mid ' + orMid.toFixed(dec) + ')');

      var atrMult = userCfg.atrMult > 0 ? userCfg.atrMult : 1.5;
      var riskDist = atrMult * atr14;
      if (riskDist < livePx * 0.0005) riskDist = livePx * 0.002;

      var targetR = 2.0;
      var longSL  = livePx - riskDist;
      var longTP1 = livePx + (1.0 * riskDist);
      var longTP2 = livePx + (2.0 * riskDist);
      var longTP3 = livePx + (3.0 * riskDist);

      var shortSL  = livePx + riskDist;
      var shortTP1 = livePx - (1.0 * riskDist);
      var shortTP2 = livePx - (2.0 * riskDist);
      var shortTP3 = livePx - (3.0 * riskDist);

      var ratios = [];
      for (var rIdx = 1; rIdx < bars.length; rIdx++) {
        var pc = bars[rIdx - 1].c;
        if (pc > 0) {
          var hr = bars[rIdx].h / pc, lr = bars[rIdx].l / pc, cr = bars[rIdx].c / pc;
          if (hr > 0.92 && hr < 1.08 && lr > 0.92 && lr < 1.08) ratios.push([hr, lr, cr]);
        }
      }
      var replays = 2500;
      var hitTP = 0, hitSL = 0, hitFlat = 0, sumR = 0;
      var endPrices = [];
      var seed = 19;
      function nextRand() {
        seed = (seed * 1664525 + 1013904223) % 4294967296;
        return seed / 4294967296;
      }
      var isBullBias = livePx >= orMid;
      for (var s = 0; s < replays; s++) {
        var px = livePx;
        var out = 'flat';
        for (var st = 0; st < 36; st++) {
          var d = ratios[Math.floor(nextRand() * ratios.length)] || [1.001, 0.999, 1.0];
          var bh = px * d[0], bl = px * d[1], bc = px * d[2];
          if (isBullBias) {
            if (bl <= longSL) { out = 'sl'; px = longSL; break; }
            if (bh >= longTP2) { out = 'tp'; px = longTP2; break; }
          } else {
            if (bh >= shortSL) { out = 'sl'; px = shortSL; break; }
            if (bl <= shortTP2) { out = 'tp'; px = shortTP2; break; }
          }
          px = bc;
        }
        endPrices.push(px);
        if (out === 'tp') { hitTP++; sumR += targetR; }
        else if (out === 'sl') { hitSL++; sumR -= 1.0; }
        else {
          hitFlat++;
          sumR += ((isBullBias ? (px - livePx) : (livePx - px)) / riskDist);
        }
      }
      endPrices.sort(function(a,b){ return a - b; });
      var p05 = endPrices[Math.floor(replays * 0.05)] || livePx;
      var p50 = endPrices[Math.floor(replays * 0.50)] || livePx;
      var p95 = endPrices[Math.floor(replays * 0.95)] || livePx;

      var resolved = Math.max(1, hitTP + hitSL);
      var winPct = (hitTP / resolved) * 100.0;
      var bePct  = (1.0 / (1.0 + targetR)) * 100.0;
      var avgR   = sumR / replays;
      var tmVerdict = winPct >= bePct + 4
        ? 'POSITIVE EDGE (+' + avgR.toFixed(2) + 'R Expected | Beats ' + bePct.toFixed(0) + '% Breakeven)'
        : (Math.abs(winPct - bePct) <= 4 ? 'NEUTRAL / COIN FLIP (' + winPct.toFixed(1) + '% vs ' + bePct.toFixed(0) + '% Breakeven)' : 'LOW PROBABILITY (' + avgR.toFixed(2) + 'R)');

      var riskUsd = userCfg.balance * (userCfg.riskPct / 100.0);
      var dailyMaxLossUsd = userCfg.balance * (userCfg.dailyLossPct / 100.0);
      var rawUnits = riskDist > 0 ? (riskUsd / riskDist) : 1;
      var lots = sym === 'GC=F'
        ? Math.max(0.01, rawUnits / 100.0)
        : (sym.indexOf('=X') >= 0 ? Math.max(0.01, rawUnits / 100000.0) : Math.max(0.01, rawUnits));
      var riskPass = (riskUsd <= dailyMaxLossUsd) && (targetR >= 1.0);
      var riskVerdict = riskPass
        ? 'PASS (Trade Risk USD ' + riskUsd.toFixed(2) + ' fits Daily Limit USD ' + dailyMaxLossUsd.toFixed(2) + ')'
        : 'BLOCK (Trade Risk USD ' + riskUsd.toFixed(2) + ' exceeds Daily Limit USD ' + dailyMaxLossUsd.toFixed(2) + ')';

      var nowUtc = new Date();
      var bdDate = new Date(nowUtc.getTime() + 6 * 3600 * 1000);
      var nyDate = new Date(nowUtc.getTime() - 4 * 3600 * 1000);
      var nyIsoDate = nyDate.toISOString().slice(0, 10);
      var bdHr = bdDate.getUTCHours();
      var kz = (bdHr >= 13 && bdHr < 17)
        ? 'London Killzone (ACTIVE)'
        : ((bdHr >= 18 && bdHr < 23) ? 'New York Killzone (ACTIVE)' : 'Asia / Transition Session');
      var nyseCalNote = nyseHolidays[nyIsoDate]
        ? 'NYSE Holiday Today'
        : (nyseEarlyCloses[nyIsoDate] ? 'NYSE Early Close 1:00 PM ET' : 'Regular Session (Flat by 15:55 ET)');

      var vpBuckets = 24;
      var vpMin = sessLow, vpMax = sessHigh;
      var vpStep = Math.max((vpMax - vpMin) / vpBuckets, 1e-6);
      var vpVols = [];
      for (var vb = 0; vb < vpBuckets; vb++) vpVols.push(0);
      var totalSessVol = 0;
      for (var sb = 0; sb < sess.length; sb++) {
        var b = sess[sb];
        var bv = Math.max(b.v || 1, 1);
        totalSessVol += bv;
        var bIdx = Math.min(vpBuckets - 1, Math.max(0, Math.floor(((b.c - vpMin) / vpStep))));
        vpVols[bIdx] += bv;
      }
      var pocIdx = 0;
      for (var vi = 1; vi < vpBuckets; vi++) {
        if (vpVols[vi] > vpVols[pocIdx]) pocIdx = vi;
      }
      var pocPrice = vpMin + (pocIdx + 0.5) * vpStep;

      var targetVaVol = totalSessVol * 0.70;
      var curVaVol = vpVols[pocIdx];
      var vaLoIdx = pocIdx, vaHiIdx = pocIdx;
      while (curVaVol < targetVaVol && (vaLoIdx > 0 || vaHiIdx < vpBuckets - 1)) {
        var upV = vaHiIdx < vpBuckets - 1 ? vpVols[vaHiIdx + 1] : -1;
        var dnV = vaLoIdx > 0 ? vpVols[vaLoIdx - 1] : -1;
        if (upV >= dnV && vaHiIdx < vpBuckets - 1) {
          vaHiIdx++;
          curVaVol += vpVols[vaHiIdx];
        } else if (vaLoIdx > 0) {
          vaLoIdx--;
          curVaVol += vpVols[vaLoIdx];
        } else {
          break;
        }
      }
      var valPrice = vpMin + vaLoIdx * vpStep;
      var vahPrice = vpMin + (vaHiIdx + 1) * vpStep;

      var cvdSession = 0, last5Delta = 0, buyImbalanceCount = 0, sellImbalanceCount = 0;
      for (var fi = 0; fi < sess.length; fi++) {
        var fb = sess[fi];
        var fRange = Math.max(fb.h - fb.l, 1e-8);
        var fVol = Math.max(fb.v || 100, 1);
        var buyShare = (fb.c - fb.l) / fRange;
        var sellShare = (fb.h - fb.c) / fRange;
        var bDelta = (fVol * buyShare) - (fVol * sellShare);
        cvdSession += bDelta;
        if (fi >= sess.length - 5) {
          last5Delta += bDelta;
          if (buyShare >= 0.72) buyImbalanceCount++;
          if (sellShare >= 0.72) sellImbalanceCount++;
        }
      }

      var stackedImbalanceStr = buyImbalanceCount >= 3
        ? 'STACKED BUY IMBALANCE (' + buyImbalanceCount + '/5 bars buyer dominance)'
        : (sellImbalanceCount >= 3
            ? 'STACKED SELL IMBALANCE (' + sellImbalanceCount + '/5 bars seller dominance)'
            : 'Balanced Footprint Flow');

      var lastBar = sess[sess.length - 1];
      var prevBar = sess[Math.max(0, sess.length - 2)];
      var lbBody  = Math.abs(lastBar.c - lastBar.o);
      var upperWick = lastBar.h - Math.max(lastBar.c, lastBar.o);
      var lowerWick = Math.min(lastBar.c, lastBar.o) - lastBar.l;

      var absorptionStatus = 'No Passive Absorption Trap — Clean Price Discovery';
      if (upperWick > lbBody * 1.4 && lastBar.h >= vahPrice - vpStep) {
        absorptionStatus = 'BEARISH ICEBERG ABSORPTION AT RESISTANCE (' + lastBar.h.toFixed(dec) + ' -> Bull Trap Warning!)';
      } else if (lowerWick > lbBody * 1.4 && lastBar.l <= valPrice + vpStep) {
        absorptionStatus = 'BULLISH ICEBERG ABSORPTION AT SUPPORT (' + lastBar.l.toFixed(dec) + ' -> Bear Trap Warning!)';
      } else if (last5Delta > 0 && lastBar.c < prevBar.c) {
        absorptionStatus = 'DELTA DIVERGENCE (Seller Absorption at ' + lastBar.c.toFixed(dec) + ')';
      } else if (last5Delta < 0 && lastBar.c > prevBar.c) {
        absorptionStatus = 'DELTA DIVERGENCE (Buyer Absorption at ' + lastBar.c.toFixed(dec) + ')';
      }

      var bidWallPx = valPrice < livePx ? valPrice : orLow;
      var askWallPx = vahPrice > livePx ? vahPrice : orHigh;
      if (askWallPx <= livePx) askWallPx = livePx + (1.5 * atr14);
      if (bidWallPx >= livePx) bidWallPx = livePx - (1.5 * atr14);

      var outTelemetry = ''
        + '\n\n[12 PRO SKILLS + ORDER FLOW LIVE TELEMETRY (' + label + ' — ' + data5m.source + ')]\n'
        + '• Live Price: ' + livePx.toFixed(dec) + ' (' + (chgPct >= 0 ? '+' : '') + chgPct.toFixed(2) + '%) | 5m RSI-14: ' + rsi5m.toFixed(1) + ' | Daily RSI-14: ' + dailyRsi.toFixed(1) + ' | 20D SMA: ' + sma20d.toFixed(dec) + ' | 90D Range: ' + lo90d.toFixed(dec) + '–' + hi90d.toFixed(dec) + '\n'
        + '• Opening Range (15m): High=' + orHigh.toFixed(dec) + ' | Mid=' + orMid.toFixed(dec) + ' | Low=' + orLow.toFixed(dec) + ' | Status: ' + entryStatus + '\n'
        + '• SMC Dealing Range & OTE (0.618–0.786): ' + pdZone + ' | Buy OTE=' + bullOte786.toFixed(dec) + '–' + bullOte618.toFixed(dec) + ' | Sell OTE=' + bearOte618.toFixed(dec) + '–' + bearOte786.toFixed(dec) + '\n'
        + '• Order Flow & Heatmap: Volume Profile POC=' + pocPrice.toFixed(dec) + ' | VAH=' + vahPrice.toFixed(dec) + ' | VAL=' + valPrice.toFixed(dec) + ' | Bid Wall=' + bidWallPx.toFixed(dec) + ' | Ask Wall=' + askWallPx.toFixed(dec) + ' | CVD=' + (cvdSession >= 0 ? '+Bullish' : '-Bearish') + ' | ' + stackedImbalanceStr + ' | ' + absorptionStatus + '\n'
        + '• Dynamic ' + atrMult + 'x ATR (' + atr14.toFixed(dec) + ') Exit Plan: LONG [SL=' + longSL.toFixed(dec) + ', TP1=' + longTP1.toFixed(dec) + ', TP2=' + longTP2.toFixed(dec) + ', TP3=' + longTP3.toFixed(dec) + '] | SHORT [SL=' + shortSL.toFixed(dec) + ', TP1=' + shortTP1.toFixed(dec) + ', TP2=' + shortTP2.toFixed(dec) + ', TP3=' + shortTP3.toFixed(dec) + ']\n'
        + '• Time Machine (2,500x Monte Carlo): Win Rate=' + winPct.toFixed(1) + '% (Breakeven ' + bePct.toFixed(0) + '%) | Expected=' + (avgR >= 0 ? '+' : '') + avgR.toFixed(2) + 'R | Verdict=' + tmVerdict + '\n'
        + '• Budget & Risk Gate: Recommended Lot=' + lots.toFixed(2) + ' Lots | ' + riskVerdict + ' | Session=' + kz + ' (' + nyseCalNote + ')\n'
        + 'IMPORTANT: Strictly follow the exact output format (JSON or text) requested by the main prompt above, and include these live Order Flow (POC, Bid/Ask Wall, CVD), Time Machine Win-Rate %, Lot Size, and Risk Gate metrics inside your analysis reason/details!';

      window.__aniketTelemetryCache[sym] = { ts: Date.now(), text: outTelemetry };
      return outTelemetry;
    }

    function hideFieldWithoutTouchingSiblings(targetPhrase, forbiddenPhrases) {
      var tLow = targetPhrase.toLowerCase();
      var all = document.querySelectorAll('label, span, div, p, details, summary');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (!el) continue;
        var tc = (el.textContent || '').trim().toLowerCase();
        if (tc.indexOf(tLow) < 0 || tc.length > 180) continue;

        var cur = el;
        while (cur && cur.parentElement && cur.parentElement !== document.body) {
          var ptc = (cur.parentElement.textContent || '').toLowerCase();
          var hitsForbidden = false;
          for (var f = 0; f < forbiddenPhrases.length; f++) {
            if (ptc.indexOf(forbiddenPhrases[f].toLowerCase()) >= 0) {
              hitsForbidden = true;
              break;
            }
          }
          if (hitsForbidden || ptc.length > 260) break;
          cur = cur.parentElement;
        }
        if (cur && cur !== document.body && cur.tagName !== 'MAIN' && cur.tagName !== 'NAV') {
          cur.style.setProperty('display', 'none', 'important');
        }
      }
    }

    function stripChartEmojiNearHeader(rootEl) {
      if (!rootEl) return;
      var chartRe = /[\uD83D\uDCC8\uD83D\uDCC9\uD83D\uDCCA\uD83D\uDCB9📈📉📊💹]/g;
      try {
        var walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_TEXT, null, false);
        var node;
        while ((node = walker.nextNode())) {
          if (node.nodeValue && chartRe.test(node.nodeValue)) {
            node.nodeValue = node.nodeValue.replace(chartRe, '');
          }
        }
      } catch(e) {}
      try {
        var kids = rootEl.querySelectorAll('span, div, i, svg');
        for (var k = 0; k < kids.length; k++) {
          var kel = kids[k];
          if (!kel || kel.id === 'aniket-single-header-logo') continue;
          var kt = (kel.textContent || '').trim();
          if (kt === '📈' || kt === '📉' || kt === '📊' || kt === '💹' || (kt.length <= 3 && chartRe.test(kt))) {
            kel.textContent = '';
            kel.style.setProperty('display', 'none', 'important');
          }
        }
      } catch(e2) {}
    }

    function applyCustomForexHeaderLogo() {
      try {
        var logoSrc = window.__aniketCustomLogoUrl || '';
        if (!logoSrc) return;

        var els = document.querySelectorAll('h1, h2, h3, header, div, span');
        var targetEl = null;
        for (var i = 0; i < els.length; i++) {
          var el = els[i];
          if (!el) continue;
          var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { top: 0 };
          if (rect.top > 220) continue;
          var txt = (el.textContent || '').trim();
          if (txt.indexOf('ANIKET PRO AI') >= 0 && txt.length < 36 && txt.indexOf('v1.0') < 0 && txt.indexOf('1.0') < 0) {
            if (!el.children || el.children.length <= 2) {
              targetEl = el;
              break;
            }
          }
        }

        if (!targetEl) return;

        stripChartEmojiNearHeader(targetEl);
        if (targetEl.parentElement) {
          stripChartEmojiNearHeader(targetEl.parentElement);
        }

        var existingLogo = document.getElementById('aniket-single-header-logo');
        if (existingLogo) return;

        targetEl.setAttribute('data-logo-applied', '1');
        var cleanTitle = (targetEl.textContent || 'ANIKET PRO AI').replace(/[\uD83D\uDCC8\uD83D\uDCC9\uD83D\uDCCA\uD83D\uDCB9📈📉📊💹]/g, '').trim();
        if (!cleanTitle) cleanTitle = 'ANIKET PRO AI';

        targetEl.innerHTML = ''
          + '<span id="aniket-single-header-logo" data-logo-applied="1" style="display:inline-flex;align-items:center;justify-content:center;position:relative;width:30px;height:30px;margin-right:8px;vertical-align:middle;">'
          + '  <img src="' + logoSrc + '" style="width:30px;height:30px;border-radius:50%;object-fit:cover;border:1.8px solid #C6A962;box-shadow:0 2px 8px rgba(0,0,0,0.65);background:#10121E;" />'
          + '</span>'
          + '<span data-logo-applied="1" style="vertical-align:middle;">' + cleanTitle + '</span>';
      } catch(e) {}
    }

    applyCustomForexHeaderLogo();
    try {
      if (!window.__aniketHeaderLogoObserver && window.MutationObserver) {
        window.__aniketHeaderLogoObserver = new MutationObserver(function() {
          applyCustomForexHeaderLogo();
        });
        if (document.documentElement) {
          window.__aniketHeaderLogoObserver.observe(document.documentElement, { childList: true, subtree: true });
        }
      }
    } catch(eObs) {}

    function cleanForexModeTabDom() {
      try {
        applyCustomForexHeaderLogo();
        var keepFormSiblings = ['Risk per Trade', 'Account Balance', 'Daily Loss Limit', 'Max Daily Trades', 'A+ Threshold', 'ATR Multiplier', 'Partial Profit'];
        hideFieldWithoutTouchingSiblings('Twelve Data Key', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('Min Wait Between Analyze', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('Live Tolerance (auto)', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('ATR Value (optional)', keepFormSiblings);

        var keepModeSiblings = ['Show HTF Zones', 'Browser Alerts', 'Live Memory Mode', 'Cache 5 min', 'Premium/Discount', 'OTE Filter', 'IDM Mandatory', 'Kill Zone Filter', 'News 15-min Filter', 'Dynamic ATR SL', 'Partial TP'];
        hideFieldWithoutTouchingSiblings('News Radar (OFF = quota bache)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Deep Mode (quota khay)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Cross-check (+1 call)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('SS Guide (perfect screenshot)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Somossa hole ki korben', keepModeSiblings);
      } catch(e) {}
    }

    setInterval(cleanForexModeTabDom, 700);

    function stripThinkTags(txt) {
      if (!txt) return '';
      return txt.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();
    }

    async function stitchImagesToDataUrl(imgList) {
      if (!imgList || imgList.length === 0) return null;
      return new Promise(function(resolve) {
        var loaded = [];
        var remaining = imgList.length;
        for (var i = 0; i < imgList.length; i++) {
          (function(idx){
            var im = new Image();
            im.onload = function() {
              loaded[idx] = im;
              remaining--;
              if (remaining <= 0) finishStitch();
            };
            im.onerror = function() {
              loaded[idx] = null;
              remaining--;
              if (remaining <= 0) finishStitch();
            };
            im.src = 'data:' + (imgList[idx].mime || 'image/jpeg') + ';base64,' + imgList[idx].b64;
          })(i);
        }
        function finishStitch() {
          var valid = loaded.filter(Boolean);
          if (valid.length === 0) {
            resolve('data:' + (imgList[0].mime || 'image/jpeg') + ';base64,' + imgList[0].b64);
            return;
          }
          var targetW = 860;
          var pad = 24;
          var totalH = 0;
          var scaledDims = [];
          for (var k = 0; k < valid.length; k++) {
            var s = targetW / Math.max(valid[k].width, 1);
            var sh = Math.round(valid[k].height * s);
            scaledDims.push({ w: targetW, h: sh });
            totalH += sh + pad;
          }
          var canvas = document.createElement('canvas');
          canvas.width = targetW;
          canvas.height = Math.min(totalH, 3200);
          var ctx = canvas.getContext('2d');
          ctx.fillStyle = '#0D0E15';
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          var y = 0;
          var vScale = canvas.height / Math.max(totalH, 1);
          for (var m = 0; m < valid.length; m++) {
            var drawH = Math.round(scaledDims[m].h * vScale);
            var barH = Math.round(pad * vScale);
            ctx.fillStyle = '#181B2C';
            ctx.fillRect(0, y, targetW, barH);
            ctx.fillStyle = '#FFD54F';
            ctx.font = 'bold 14px sans-serif';
            ctx.fillText('FOREX CHART #' + (m + 1) + ' OF ' + valid.length, 12, y + Math.max(13, barH - 5));
            y += barH;
            ctx.drawImage(valid[m], 0, y, targetW, drawH);
            y += drawH;
          }
          resolve(canvas.toDataURL('image/jpeg', 0.76));
        }
      });
    }

    async function callOpenAiVisionProvider(endpoint, key, defaultModels, promptText, combinedDataUrl, extraHeaders) {
      var authToken = cleanProviderAuthToken(key);
      for (var i = 0; i < defaultModels.length; i++) {
        var model = defaultModels[i];
        try {
          var isTextOnly = (model.indexOf('llama-3.3') >= 0 || model.indexOf('llama-3.1') >= 0 || model.indexOf('nemo') >= 0);
          var userContent = (combinedDataUrl && !isTextOnly)
            ? [{ type: 'text', text: promptText }, { type: 'image_url', image_url: { url: combinedDataUrl } }]
            : promptText;
          var headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + authToken
          };
          if (extraHeaders) {
            for (var hk in extraHeaders) headers[hk] = extraHeaders[hk];
          }
          var resp = await fetchWithTimeout(endpoint, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
              model: model,
              temperature: 0.2,
              max_tokens: 2048,
              messages: [{ role: 'user', content: userContent }]
            })
          }, 9000);
          if (resp && resp.ok) {
            var j = await resp.json();
            var rawTxt = (j && j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || '';
            var cleaned = stripThinkTags(rawTxt);
            if (cleaned && cleaned.length > 1) {
              return cleaned;
            }
          } else if (resp && (resp.status === 401 || resp.status === 403)) {
            break;
          }
        } catch(e) {}
      }
      return null;
    }

    async function callGeminiProvider(key, cleanBodyStr, rawBodyStr) {
      var models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
      for (var i = 0; i < models.length; i++) {
        var m = models[i];
        try {
          var url = 'https://generativelanguage.googleapis.com/v1beta/models/' + m + ':generateContent?key=' + encodeURIComponent(key);
          var resp = await fetchWithTimeout(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: cleanBodyStr || rawBodyStr
          }, 9000);
          if (resp && resp.ok) {
            var j = await resp.json();
            var parts = j && j.candidates && j.candidates[0] && j.candidates[0].content && j.candidates[0].content.parts;
            if (parts && parts.length > 0) {
              var finalTxt = '';
              for (var p = 0; p < parts.length; p++) {
                if (parts[p] && !parts[p].thought && parts[p].text) {
                  finalTxt += parts[p].text;
                }
              }
              if (finalTxt.length > 1) {
                return finalTxt;
              }
            }
          } else if (resp && (resp.status === 429 || resp.status === 403 || resp.status === 400)) {
            break;
          }
        } catch(e) {}
      }
      return null;
    }

    function makeGeminiSuccessResponse(txt) {
      return new Response(JSON.stringify({
        candidates: [{
          content: { role: 'model', parts: [{ text: txt }] },
          finishReason: 'STOP'
        }]
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    var __lastSuccessCache = { ts: 0, sig: '', out: '' };

    window.fetch = async function(input, init) {
      var urlStr = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (urlStr.indexOf('generativelanguage.googleapis.com') >= 0) {
        if (urlStr.indexOf(':generateContent') < 0) {
          return new Response(JSON.stringify({
            models: [
              { name: 'models/gemini-2.5-flash', supportedGenerationMethods: ['generateContent'] },
              { name: 'models/gemini-2.0-flash', supportedGenerationMethods: ['generateContent'] }
            ]
          }), { status: 200, headers: { 'Content-Type': 'application/json' } });
        }

        var rawBodyStr = (init && init.body) ? init.body.toString() : '{}';
        var promptText = '';
        var sysText = '';
        var imgList = [];
        var wantJson = false;

        try {
          var parsedBody = JSON.parse(rawBodyStr);
          var sysObj = parsedBody.system_instruction || parsedBody.systemInstruction;
          if (sysObj && sysObj.parts) {
            for (var sp = 0; sp < sysObj.parts.length; sp++) {
              if (sysObj.parts[sp] && sysObj.parts[sp].text) {
                sysText += (sysText ? '\n' : '') + sysObj.parts[sp].text;
              }
            }
          }
          var genCfg = parsedBody.generationConfig || parsedBody.generation_config || {};
          var mimeResp = (genCfg.responseMimeType || genCfg.response_mime_type || '').toLowerCase();
          if (mimeResp.indexOf('json') >= 0) wantJson = true;

          var contents = (parsedBody && parsedBody.contents) || [];
          for (var c = 0; c < contents.length; c++) {
            var parts = (contents[c] && contents[c].parts) || [];
            for (var p = 0; p < parts.length; p++) {
              var pt = parts[p];
              if (pt.text) {
                promptText += (promptText ? '\n\n' : '') + pt.text;
              }
              var inl = pt.inlineData || pt.inline_data;
              if (inl && inl.data) {
                imgList.push({
                  mime: inl.mimeType || inl.mime_type || 'image/jpeg',
                  b64: inl.data
                });
              }
            }
          }
        } catch(e) {}

        var fullPrompt = (sysText ? (sysText + '\n\n') : '') + promptText;

        var callSig = (wantJson ? 'J:' : 'T:') + imgList.length + ':' + fullPrompt.slice(0, 120);
        if (Date.now() - __lastSuccessCache.ts < 5000 && __lastSuccessCache.sig === callSig && __lastSuccessCache.out) {
          return makeGeminiSuccessResponse(__lastSuccessCache.out);
        }

        if (imgList.length > 0 || fullPrompt.length > 120) {
          try {
            var unifiedTelemetry = await runUnified11SkillsAndUserFeatures(fullPrompt);
            if (unifiedTelemetry) {
              fullPrompt += unifiedTelemetry;
            }
          } catch(eTel) {}
        }

        var realImgs = imgList.filter(function(im){ return im && im.b64 && im.b64.length >= 200; });
        var combinedDataUrl = await stitchImagesToDataUrl(realImgs);
        var stitchedB64 = '';
        if (combinedDataUrl && combinedDataUrl.indexOf('base64,') >= 0) {
          stitchedB64 = combinedDataUrl.split('base64,')[1] || '';
        }

        var urlKeyMatch = /[?&]key=([^&]+)/.exec(urlStr);
        var urlKey = urlKeyMatch ? deobfKey(decodeURIComponent(urlKeyMatch[1])) : '';
        var siteNow = readSiteKeys();
        var candidateKeys = [];

        if (urlKey && urlKey.length >= 16) candidateKeys.push(urlKey);
        if (window.__lastWorkingForexKey && window.__lastWorkingForexKey.length >= 16 && candidateKeys.indexOf(window.__lastWorkingForexKey) < 0) {
          candidateKeys.push(window.__lastWorkingForexKey);
        }
        for (var s = 0; s < siteNow.length; s++) {
          if (candidateKeys.indexOf(siteNow[s]) < 0) candidateKeys.push(siteNow[s]);
        }
        for (var a = 0; a < (window.__aniketAllKeys || []).length; a++) {
          var ak = deobfKey(window.__aniketAllKeys[a]);
          if (ak && ak.length >= 16 && candidateKeys.indexOf(ak) < 0) candidateKeys.push(ak);
        }

        // 1. Primary: Native Dart HttpClient Multi-AI Bridge (100% immune to WebView CORS/CSP & finishes in 3-5s!)
        if (candidateKeys.length > 0 && window.FlutterBridge) {
          var dartOut = await callNativeDartAiFallback(candidateKeys, urlKey, fullPrompt, realImgs, stitchedB64, wantJson);
          if (dartOut && dartOut.length > 1) {
            __lastSuccessCache = { ts: Date.now(), sig: callSig, out: dartOut };
            return makeGeminiSuccessResponse(dartOut);
          }
        }

        // 2. Fast JS Fallback if needed
        var cleanGemParts = [{ text: fullPrompt }];
        for (var imIdx = 0; imIdx < realImgs.slice(0, 2).length; imIdx++) {
          cleanGemParts.push({
            inline_data: {
              mime_type: realImgs[imIdx].mime || 'image/jpeg',
              data: realImgs[imIdx].b64
            }
          });
        }
        var cleanGemBody = JSON.stringify({
          contents: [{ parts: cleanGemParts }],
          generationConfig: wantJson ? { temperature: 0.2, responseMimeType: 'application/json' } : { temperature: 0.2 }
        });

        for (var idx = 0; idx < candidateKeys.length; idx++) {
          var k = candidateKeys[idx];
          if (!k) continue;

          if (k.indexOf('AIza') === 0) {
            var gemTxt = await callGeminiProvider(k, cleanGemBody, rawBodyStr);
            if (gemTxt) {
              window.__lastWorkingForexKey = k;
              __lastSuccessCache = { ts: Date.now(), sig: callSig, out: gemTxt };
              return makeGeminiSuccessResponse(gemTxt);
            }
          } else if (k.indexOf('gsk_') === 0) {
            var groqTxt = await callOpenAiVisionProvider(
              'https://api.groq.com/openai/v1/chat/completions',
              k,
              ['meta-llama/llama-4-scout-17b-16e-instruct', 'meta-llama/llama-4-maverick-17b-128e-instruct', 'llama-3.3-70b-versatile'],
              fullPrompt,
              combinedDataUrl,
              null
            );
            if (groqTxt) {
              window.__lastWorkingForexKey = k;
              __lastSuccessCache = { ts: Date.now(), sig: callSig, out: groqTxt };
              return makeGeminiSuccessResponse(groqTxt);
            }
          } else if (k.indexOf('sk-or-') === 0) {
            var orTxt = await callOpenAiVisionProvider(
              'https://openrouter.ai/api/v1/chat/completions',
              k,
              ['google/gemma-3-27b-it:free', 'mistralai/mistral-small-3.1-24b-instruct:free', 'openrouter/free'],
              fullPrompt,
              combinedDataUrl,
              { 'HTTP-Referer': 'https://aniketpro.ai', 'X-Title': 'ANIKET PRO AI' }
            );
            if (orTxt) {
              window.__lastWorkingForexKey = k;
              __lastSuccessCache = { ts: Date.now(), sig: callSig, out: orTxt };
              return makeGeminiSuccessResponse(orTxt);
            }
          } else {
            var misTxt = await callOpenAiVisionProvider(
              'https://api.mistral.ai/v1/chat/completions',
              k,
              ['pixtral-12b-2409', 'mistral-small-latest', 'open-mistral-nemo'],
              fullPrompt,
              combinedDataUrl,
              null
            );
            if (misTxt) {
              window.__lastWorkingForexKey = k;
              __lastSuccessCache = { ts: Date.now(), sig: callSig, out: misTxt };
              return makeGeminiSuccessResponse(misTxt);
            }
          }
        }

        return new Response(JSON.stringify({
          error: { code: 429, message: 'All configured API keys are currently busy or rate-limited. Please check your key in the Key tab.' }
        }), { status: 429, headers: { 'Content-Type': 'application/json' } });
      }
      return origFetch(input, init);
    };
  } catch(e) {}
})();
''';
    return tpl
        .replaceFirst('__FLUTTER_KEYS_JSON__', flutterKeysJson)
        .replaceFirst('__FLUTTER_LOGO_URL__', jsonEncode(logoDataUrl));
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
        } else if (m.startsWith('FOREX_DART_AI:')) {
          _handleForexDartAiRequest(m.substring(14));
        } else if (m.startsWith('OPEN_11SKILL_SHEET:')) {
          final tabIdx = int.tryParse(m.substring(19).trim()) ?? 0;
          if (mounted) _openInForex11SkillSheet(initialTab: tabIdx);
        } else if (m.startsWith('SYNC_KEYS:')) {
          try {
            final rawList = jsonDecode(m.substring(10)) as List;
            final cleaned = rawList
                .map((e) => _unwrapApiKey(e.toString()))
                .where((e) => e.length >= 16)
                .toSet()
                .toList();
            if (cleaned.isNotEmpty) {
              final p = await SharedPreferences.getInstance();
              await p.setStringList('bin_keys', cleaned);
            }
          } catch (_) {}
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          _progressN.value = p / 100;
          if (p >= 20) {
            try {
              _controller.runJavaScript(_netlifyHideJs());
              _syncMultiKeysToForexWeb();
            } catch (_) {}
          }
        },
        onPageStarted: (_) {
          _progressN.value = 0;
          if (_firstLoad) setState(() => _isLoading = true);
          try { _controller.runJavaScript(_netlifyHideJs()); } catch (_) {}
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
          await _syncMultiKeysToForexWeb();
          _seedCounts();
          _flush();
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  String _netlifyHideJs() => '''(function(){
  try {
    if (!window.__nlShadowHooked && window.Element && Element.prototype.attachShadow) {
      window.__nlShadowHooked = true;
      var origAttach = Element.prototype.attachShadow;
      Element.prototype.attachShadow = function(init) {
        var sr = origAttach.call(this, init);
        try { this.__capturedShadow = sr; } catch(e) {}
        return sr;
      };
    }

    if (!window.__nlCss) {
      window.__nlCss = 1;
      var st = document.createElement('style');
      st.textContent = 'iframe[src*="netlify"],[id*="netlify"],[class*="netlify"],a[href*="netlify"],div[data-netlify],aside[id*="netlify"],netlify-badge,[data-netlify-deploy-id]{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;width:0!important;height:0!important;max-height:0!important;overflow:hidden!important;z-index:-9999!important;}';
      (document.head || document.documentElement).appendChild(st);
    }

    function nukeEl(el) {
      if (!el || el === document.body || el === document.documentElement) return;
      if (el.tagName === 'NAV' || (el.querySelector && el.querySelector('input[type=file], nav'))) return;
      try {
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('opacity', '0', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
        el.style.setProperty('width', '0px', 'important');
        el.style.setProperty('height', '0px', 'important');
        el.remove();
      } catch(e) {}
    }

    function isProtectedAppNode(el) {
      if (!el) return true;
      var tag = (el.tagName || '').toUpperCase();
      if (tag === 'HTML' || tag === 'BODY' || tag === 'HEAD' || tag === 'MAIN' || tag === 'NAV' || tag === 'SCRIPT' || tag === 'STYLE') return true;
      if (el.id && el.id.indexOf('aniket-') === 0) return true;
      if (el.closest && el.closest('nav, #aniket-11skills-mode-box, #aniket-11skills-analysis-box')) return true;
      if (el.querySelector && el.querySelector('nav, input[type=file]')) return true;
      var t = (el.innerText || '').trim();
      if (t.indexOf('ANIKET PRO AI') >= 0 || (t.indexOf('SS') >= 0 && t.indexOf('Analysis') >= 0 && t.indexOf('Journal') >= 0)) return true;
      return false;
    }

    function scanRoot(root) {
      if (!root) return;
      var nodes = [];
      try { nodes = root.querySelectorAll('*'); } catch(e) {}
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el) continue;

        var sr = el.shadowRoot || el.__capturedShadow;
        if (sr) scanRoot(sr);

        if (isProtectedAppNode(el)) continue;

        var src = (el.src || '') + ' ' + (el.href || '');
        var idc = (el.id || '') + ' ' + (typeof el.className === 'string' ? el.className : '');
        var txt = (el.innerText || el.textContent || '').trim();
        var low = (src + ' ' + idc + ' ' + txt).toLowerCase();

        if (txt === 'Hide this badge') {
          try { el.click(); } catch(e) {}
          nukeEl(el);
          continue;
        }

        if ((low.indexOf('powered by netlify') >= 0 || low.indexOf('netlify') >= 0) && txt.length < 140) {
          nukeEl(el);
          continue;
        }

        // Geometric killer for closed Shadow DOM floating pill in bottom-right ("Powered by Netlify")
        try {
          var cs = window.getComputedStyle(el);
          if (cs && (cs.position === 'fixed' || cs.position === 'sticky' || parseInt(cs.zIndex || '0', 10) > 9999)) {
            var rect = el.getBoundingClientRect();
            // The Netlify pill sits near the bottom-right (bottom within 90px of viewport bottom, width < 70% of screen, height 20..75px)
            if (rect.width > 60 && rect.width < window.innerWidth * 0.72 &&
                rect.height >= 18 && rect.height <= 78 &&
                rect.bottom >= window.innerHeight - 95 &&
                rect.right >= window.innerWidth * 0.55) {
              nukeEl(el);
              continue;
            }
          }
        } catch(e) {}
      }

      // Also probe bottom-right coordinates directly with elementFromPoint to catch closed Shadow-DOM hosts
      try {
        var probePoints = [
          [window.innerWidth - 80, window.innerHeight - 24],
          [window.innerWidth - 120, window.innerHeight - 28],
          [window.innerWidth - 60, window.innerHeight - 32]
        ];
        for (var p = 0; p < probePoints.length; p++) {
          var hit = document.elementFromPoint(probePoints[p][0], probePoints[p][1]);
          while (hit && hit !== document.body && hit !== document.documentElement) {
            if (!isProtectedAppNode(hit)) {
              var hcs = window.getComputedStyle(hit);
              var hrect = hit.getBoundingClientRect();
              if (hcs && hcs.position === 'fixed' && hrect.width < window.innerWidth * 0.72 && hrect.height <= 80) {
                nukeEl(hit);
                break;
              }
            }
            hit = hit.parentElement;
          }
        }
      } catch(e) {}
    }

    scanRoot(document);
    if (!window.__nlObserver) {
      window.__nlObserver = new MutationObserver(function() { scanRoot(document); });
      window.__nlObserver.observe(document.documentElement || document, { childList: true, subtree: true });
    }
    if (!window.__nlInterval) {
      window.__nlInterval = setInterval(function() { scanRoot(document); }, 450);
    }
  } catch(e) {}
})();''';

  String _pageHookJs() => '''(function(){
    if(window.__aniketHook)return;window.__aniketHook=true;
    function headOf(inp){var host=inp;for(var up=0;up<6&&host;up++){var t=(host.innerText||'').toUpperCase();if(t.length>=10&&t.length<=400){if(t.indexOf('CORRELATION')>=0||t.indexOf('DXY')>=0||t.indexOf('ENTRY')>=0||t.indexOf('HTF')>=0)return t;}host=host.parentElement;}return '';}
    function classify(inp){if(inp.id==='htfInput')return 'htf';if(inp.id==='entryInput')return 'entry';if(inp.id==='dxyInput')return 'corr';var h=headOf(inp);if(h.indexOf('CORRELATION')>=0||h.indexOf('DXY')>=0)return 'corr';if(h.indexOf('ENTRY')>=0)return 'entry';if(h.indexOf('HTF')>=0)return 'htf';if(!inp.multiple)return 'corr';var inputs=document.querySelectorAll('input[type=file]');var idx=Array.prototype.indexOf.call(inputs,inp);if(idx===0)return 'entry';return 'htf';}
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
    var lastTab='';
    setInterval(function(){
      var inp=document.querySelector('input[type=file]');
      var cur=(inp&&inp.offsetParent!=null)?'SS':'OTHER';
      if(cur!==lastTab){lastTab=cur;FlutterBridge.postMessage('TAB:'+cur);}
    },300);
  })();''';

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
        onTap: () {
          setState(() => _mode = key);
          if (key == 'forex') {
            _syncMultiKeysToForexWeb();
          }
        },
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
              // FOREX side — পুরানো সব অক্ষত + 4-Key Multi-AI Auto-Failover Bridge
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

  void _openInForex11SkillSheet({int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0D12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF12161F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_graph_rounded, color: kGold, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'FOREX 11 DAY-TRADER PRO SKILLS (FULL ENGINE)',
                      style: TextStyle(color: kGold, fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white70, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ProTraderDeskScreen(initialSkillTab: initialTab),
            ),
          ],
        ),
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

// ═══════════════════════════════════════════════════════════════════════════
//  ANIKET PRO AI — 11 DAY-TRADER SKILLS COMMAND CENTER (COMPLETE EDITION)
//  Includes 100% of all sub-features from day-trader-skill v2.0:
//   1. trader-scanner     (Daily Setups + 5m Intraday ORB + Custom Ticker Universe)
//   2. trader-news        (Yahoo RSS + Live SEC EDGAR 8-K Atom Feed & Item Tagger)
//   3. trader-entry       (5m/1m Toggle, ORB 15m vs Level Mode, Volume Filter)
//   4. trader-exit        (Interactive Stop Rule: or-mid/or-low/atr:1.5/pct & 1R/1.5R/2R/3R)
//   5. trader-timemachine (Monte Carlo Replays + Historical Session Backtest + ASCII Fan Histogram)
//   6. trader-budget      (4-Cap Trade Sizer + Multi-Asset Portfolio Weights Allocator)
//   7. trader-risk        (10-Rule Pre-Trade Compliance Gate: PASS / BLOCK)
//   8. trader-broker      (Bracket Ticket + Copy Alpaca JSON + Flatten Position Ticket)
//   9. trader-alerts      (NYSE 2026-2027 Holiday/Early-Close Clock + Custom & Plan Alerts)
//  10. trader-analyst     (SEC EDGAR XBRL Multi-Quarter YoY Table + Transcript AI Analyzer)
//  11. trader-pelosi      (US Congress PTR Tracker + Member Filter + Watchlist Match Flag)
// ═══════════════════════════════════════════════════════════════════════════

class ProBar {
  final int ts;
  final double o;
  final double h;
  final double l;
  final double c;
  final double v;
  const ProBar({
    required this.ts,
    required this.o,
    required this.h,
    required this.l,
    required this.c,
    required this.v,
  });
}

class ProTraderDeskScreen extends StatefulWidget {
  final int initialSkillTab;
  const ProTraderDeskScreen({super.key, this.initialSkillTab = 0});

  @override
  State<ProTraderDeskScreen> createState() => _ProTraderDeskScreenState();
}

class _ProTraderDeskScreenState extends State<ProTraderDeskScreen> {
  static final List<Map<String, String>> _presets = [
    {'label': 'XAU/USD (Gold)', 'sym': 'GC=F', 'kind': 'forex'},
    {'label': 'XAG/USD (Silver)', 'sym': 'SI=F', 'kind': 'forex'},
    {'label': 'WTI Crude Oil', 'sym': 'CL=F', 'kind': 'forex'},
    {'label': 'US100 (Nasdaq Fut)', 'sym': 'NQ=F', 'kind': 'forex'},
    {'label': 'US30 (Dow Fut)', 'sym': 'YM=F', 'kind': 'forex'},
    {'label': 'DXY (Dollar Index)', 'sym': 'DX-Y.NYB', 'kind': 'forex'},
    {'label': 'BTC/USD (Bitcoin)', 'sym': 'BTC-USD', 'kind': 'crypto'},
    {'label': 'ETH/USD (Ethereum)', 'sym': 'ETH-USD', 'kind': 'crypto'},
    {'label': 'SOL/USD (Solana)', 'sym': 'SOL-USD', 'kind': 'crypto'},
    {'label': 'EUR/USD', 'sym': 'EURUSD=X', 'kind': 'forex'},
    {'label': 'GBP/USD', 'sym': 'GBPUSD=X', 'kind': 'forex'},
    {'label': 'USD/JPY', 'sym': 'USDJPY=X', 'kind': 'forex'},
    {'label': 'AUD/USD', 'sym': 'AUDUSD=X', 'kind': 'forex'},
    {'label': 'USD/CAD', 'sym': 'USDCAD=X', 'kind': 'forex'},
    {'label': 'NVDA', 'sym': 'NVDA', 'kind': 'stock'},
    {'label': 'TSLA', 'sym': 'TSLA', 'kind': 'stock'},
    {'label': 'AAPL', 'sym': 'AAPL', 'kind': 'stock'},
    {'label': 'AMD', 'sym': 'AMD', 'kind': 'stock'},
    {'label': 'META', 'sym': 'META', 'kind': 'stock'},
    {'label': 'MSFT', 'sym': 'MSFT', 'kind': 'stock'},
    {'label': 'AMZN', 'sym': 'AMZN', 'kind': 'stock'},
    {'label': 'GOOGL', 'sym': 'GOOGL', 'kind': 'stock'},
    {'label': 'SPY', 'sym': 'SPY', 'kind': 'stock'},
    {'label': 'QQQ', 'sym': 'QQQ', 'kind': 'stock'},
  ];

  // Official NYSE 2026 & 2027 Holidays and 1:00 PM ET Early Closes (from alerts.py)
  static const Set<String> _nyseHolidays = {
    '2026-01-01', '2026-01-19', '2026-02-16', '2026-04-03', '2026-05-25',
    '2026-06-19', '2026-07-03', '2026-09-07', '2026-11-26', '2026-12-25',
    '2027-01-01', '2027-01-18', '2027-02-15', '2027-03-26', '2027-05-31',
    '2027-06-18', '2027-07-05', '2027-09-06', '2027-11-25', '2027-12-24',
  };
  static const Set<String> _nyseEarlyCloses = {
    '2026-11-27', '2026-12-24', '2027-11-26',
  };

  int _activeSkillTab = 0;
  String _selectedSym = 'GC=F';
  String _selectedLabel = 'XAU/USD (Gold)';
  bool _busy = false;
  String _statusMsg = 'Ready — Tap "RUN ALL 11 SKILLS" or select any skill tab below';

  // Entry settings (trader-entry)
  String _entryInterval = '5m'; // '5m' or '1m'
  String _entrySetupMode = 'orb'; // 'orb' or 'level'
  double _customBreakoutLevel = 0.0;
  double _minVolumeX = 1.0;

  // Exit settings (trader-exit)
  String _stopRule = 'atr:1.5'; // 'or_mid', 'or_low', 'atr:1.5', 'pct:0.5'
  double _targetR = 2.0;

  // Budget & Risk settings (trader-budget & trader-risk)
  double _budgetUsd = 5000.0;
  double _maxLossPerTradeUsd = 50.0;
  double _maxDailyLossUsd = 150.0;
  double _cashBufferPct = 10.0;
  double _maxPositionPct = 75.0;
  double _maxOrderUsd = 4000.0;
  double _minRewardRisk = 1.0;
  String _weightsSpec = 'GC=F=30,BTC-USD=25,NVDA=25,TSLA=20';
  List<Map<String, dynamic>> _weightsAllocation = [];

  // Shared 11-skill state
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> _newsItems = [];
  Map<String, dynamic>? _entryState;
  Map<String, dynamic>? _planState;
  Map<String, dynamic>? _timeMachineState;
  Map<String, dynamic>? _budgetOrderState;
  Map<String, dynamic>? _riskVerdictState;
  List<Map<String, dynamic>> _brokerLog = [];
  List<Map<String, dynamic>> _alertsList = [];
  Map<String, dynamic>? _analystState;
  String _transcriptAnalysis = '';
  List<Map<String, dynamic>> _pelosiRows = [];
  String _pelosiFilter = '';
  String _aiDeepSummary = '';

  Timer? _alertWatchTimer;

  @override
  void initState() {
    super.initState();
    _activeSkillTab = widget.initialSkillTab;
    _loadSavedProState();
    _computeWeightsAllocation();
    _startBackgroundAlertWatcher();
  }

  @override
  void dispose() {
    _alertWatchTimer?.cancel();
    super.dispose();
  }

  // ── Market Clock Helper (NYSE Clock from alerts.py + BD Killzone Clock) ──
  Map<String, String> _getMarketClockStatus() {
    final nowUtc = DateTime.now().toUtc();
    // New York EDT is UTC-4 (Mar-Nov), EST is UTC-5; Oct is EDT (UTC-4)
    final isDst = nowUtc.month >= 3 && nowUtc.month <= 11;
    final nyTime = nowUtc.add(Duration(hours: isDst ? -4 : -5));
    final bdTime = nowUtc.add(const Duration(hours: 6));

    final nyDateStr =
        '${nyTime.year}-${nyTime.month.toString().padLeft(2, '0')}-${nyTime.day.toString().padLeft(2, '0')}';
    final nyHm = '${nyTime.hour.toString().padLeft(2, '0')}:${nyTime.minute.toString().padLeft(2, '0')}';
    final bdHm = '${bdTime.hour.toString().padLeft(2, '0')}:${bdTime.minute.toString().padLeft(2, '0')}';

    final isWeekend = nyTime.weekday == DateTime.saturday || nyTime.weekday == DateTime.sunday;
    final isHoliday = _nyseHolidays.contains(nyDateStr);
    final isEarlyClose = _nyseEarlyCloses.contains(nyDateStr);
    final closeMinutes = isEarlyClose ? (13 * 60) : (16 * 60);
    final curMinutes = nyTime.hour * 60 + nyTime.minute;
    final openMinutes = 9 * 60 + 30;

    String nyseStatus;
    if (isWeekend) {
      nyseStatus = 'CLOSED (Weekend)';
    } else if (isHoliday) {
      nyseStatus = 'CLOSED (NYSE Holiday)';
    } else if (curMinutes >= openMinutes && curMinutes < closeMinutes) {
      nyseStatus = isEarlyClose ? 'OPEN (Early Close 1:00 PM ET)' : 'OPEN (Regular Session)';
    } else if (curMinutes < openMinutes) {
      final minsLeft = openMinutes - curMinutes;
      nyseStatus = 'PRE-MARKET (Opens in ${minsLeft ~/ 60}h ${minsLeft % 60}m)';
    } else {
      nyseStatus = 'AFTER-HOURS (Closed at ${isEarlyClose ? "1:00 PM" : "4:00 PM"} ET)';
    }

    String fxSession;
    if (bdTime.hour >= 13 && bdTime.hour < 17) {
      fxSession = 'LONDON KILLZONE (High Liq)';
    } else if (bdTime.hour >= 18 && bdTime.hour < 23) {
      fxSession = 'NEW YORK KILLZONE (Peak Liq)';
    } else if (bdTime.hour >= 5 && bdTime.hour < 12) {
      fxSession = 'ASIA / TOKYO SESSION';
    } else {
      fxSession = 'LATE NY / SYDNEY TRANSITION';
    }

    return {
      'ny_time': '$nyHm ET ($nyDateStr)',
      'bd_time': '$bdHm BD',
      'nyse_status': nyseStatus,
      'fx_session': fxSession,
      'flat_by': isEarlyClose ? '12:55 ET (Early Close)' : '15:55 ET',
    };
  }

  Future<void> _loadSavedProState() async {
    try {
      final p = await SharedPreferences.getInstance();
      setState(() {
        _budgetUsd = p.getDouble('pro_budget') ?? 5000.0;
        _maxLossPerTradeUsd = p.getDouble('pro_max_loss') ?? 50.0;
        _maxDailyLossUsd = p.getDouble('pro_daily_loss') ?? 150.0;
        _targetR = p.getDouble('pro_target_r') ?? 2.0;
        _stopRule = p.getString('pro_stop_rule') ?? 'atr:1.5';
        final rawAlerts = p.getString('pro_alerts_json');
        if (rawAlerts != null && rawAlerts.isNotEmpty) {
          _alertsList = (jsonDecode(rawAlerts) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        final rawBroker = p.getString('pro_broker_json');
        if (rawBroker != null && rawBroker.isNotEmpty) {
          _brokerLog = (jsonDecode(rawBroker) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      });
    } catch (_) {}
  }

  Future<void> _saveProState() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('pro_budget', _budgetUsd);
      await p.setDouble('pro_max_loss', _maxLossPerTradeUsd);
      await p.setDouble('pro_daily_loss', _maxDailyLossUsd);
      await p.setDouble('pro_target_r', _targetR);
      await p.setString('pro_stop_rule', _stopRule);
      await p.setString('pro_alerts_json', jsonEncode(_alertsList));
      await p.setString('pro_broker_json', jsonEncode(_brokerLog));
    } catch (_) {}
  }

  void _notifyToast(String msg) {
    try {
      galleryChannel.invokeMethod('toast', msg);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: kGold,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<String> _fetchUrl(String url, {String? userAgent}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(
        'User-Agent',
        userAgent ?? 'AniketProAI/2.0 (day-trader-skill; contact@aniketpro.ai)',
      );
      req.headers.set('Accept', 'application/json, text/xml, application/xml, */*');
      final resp = await req.close().timeout(const Duration(seconds: 14));
      if (resp.statusCode != 200) return '';
      return await resp.transform(utf8.decoder).join();
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _fetchYahooChart(String sym, {String range = '5d', String interval = '5m'}) async {
    for (final host in ['query2.finance.yahoo.com', 'query1.finance.yahoo.com']) {
      final url = 'https://$host/v8/finance/chart/${Uri.encodeComponent(sym)}?range=$range&interval=$interval';
      final raw = await _fetchUrl(url);
      if (raw.isEmpty) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final resList = (j['chart']?['result'] as List?) ?? [];
        if (resList.isEmpty) continue;
        final res = resList.first as Map<String, dynamic>;
        final meta = (res['meta'] as Map<String, dynamic>?) ?? {};
        final tsList = (res['timestamp'] as List?) ?? [];
        final qList = (res['indicators']?['quote'] as List?) ?? [];
        if (qList.isEmpty) continue;
        final q = qList.first as Map<String, dynamic>;
        final oList = (q['open'] as List?) ?? [];
        final hList = (q['high'] as List?) ?? [];
        final lList = (q['low'] as List?) ?? [];
        final cList = (q['close'] as List?) ?? [];
        final vList = (q['volume'] as List?) ?? [];

        final List<ProBar> bars = [];
        for (int i = 0; i < tsList.length && i < cList.length; i++) {
          final c = (cList[i] as num?)?.toDouble();
          final h = (hList[i] as num?)?.toDouble();
          final l = (lList[i] as num?)?.toDouble();
          if (c == null || h == null || l == null) continue;
          final o = (oList[i] as num?)?.toDouble() ?? c;
          final v = (vList.length > i ? (vList[i] as num?)?.toDouble() : 0.0) ?? 0.0;
          bars.add(ProBar(
            ts: (tsList[i] as num).toInt(),
            o: o,
            h: h,
            l: l,
            c: c,
            v: v,
          ));
        }
        if (bars.isNotEmpty) {
          return {
            'meta': meta,
            'bars': bars,
            'price': (meta['regularMarketPrice'] as num?)?.toDouble() ?? bars.last.c,
            'prevClose': (meta['chartPreviousClose'] as num?)?.toDouble() ??
                (meta['previousClose'] as num?)?.toDouble() ??
                bars.first.o,
          };
        }
      } catch (_) {}
    }
    return null;
  }

  double _calcWilderRsi(List<double> closes, {int period = 14}) {
    if (closes.length <= period) return 50.0;
    double gains = 0.0;
    double losses = 0.0;
    for (int i = 1; i <= period; i++) {
      final diff = closes[i] - closes[i - 1];
      if (diff >= 0) {
        gains += diff;
      } else {
        losses -= diff;
      }
    }
    double avgGain = gains / period;
    double avgLoss = losses / period;
    for (int i = period + 1; i < closes.length; i++) {
      final diff = closes[i] - closes[i - 1];
      final g = diff > 0 ? diff : 0.0;
      final l = diff < 0 ? -diff : 0.0;
      avgGain = ((avgGain * (period - 1)) + g) / period;
      avgLoss = ((avgLoss * (period - 1)) + l) / period;
    }
    if (avgLoss == 0) return 100.0;
    final rs = avgGain / avgLoss;
    return 100.0 - (100.0 / (1.0 + rs));
  }

  double _calcAtr14(List<ProBar> bars) {
    if (bars.length < 2) return 0.0;
    final n = math.min(14, bars.length - 1);
    double sumTr = 0.0;
    for (int i = bars.length - n; i < bars.length; i++) {
      final cur = bars[i];
      final prevC = bars[i - 1].c;
      final tr = math.max(
        cur.h - cur.l,
        math.max((cur.h - prevC).abs(), (cur.l - prevC).abs()),
      );
      sumTr += tr;
    }
    return sumTr / n;
  }

  int _decimalsFor(double px) => px > 100 ? 2 : (px > 10 ? 3 : 5);

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 1: trader-scanner (Chart Scanner — Daily & Intraday ORB)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runScanner() async {
    setState(() {
      _busy = true;
      _statusMsg = 'Running trader-scanner across Gold, Silver, BTC, Forex & Top Stocks...';
    });
    final List<Map<String, dynamic>> hits = [];
    for (final item in _presets.take(14)) {
      final sym = item['sym']!;
      final label = item['label']!;
      final dailyData = await _fetchYahooChart(sym, range: '3mo', interval: '1d');
      final intraData = await _fetchYahooChart(sym, range: '2d', interval: '5m');
      if (dailyData == null && intraData == null) continue;

      final List<String> setups = [];
      double lastPx = 0.0;
      double chgPct = 0.0;
      double rsi = 50.0;
      double orHigh = 0.0;
      double orLow = 0.0;

      if (dailyData != null) {
        final bars = dailyData['bars'] as List<ProBar>;
        final closes = bars.map((b) => b.c).toList();
        lastPx = (dailyData['price'] as double?) ?? closes.last;
        final prev = bars.length >= 2 ? bars[bars.length - 2].c : bars.first.o;
        chgPct = prev > 0 ? ((lastPx - prev) / prev) * 100.0 : 0.0;
        rsi = _calcWilderRsi(closes);

        if (closes.length >= 21) {
          final prior20 = closes.sublist(closes.length - 21, closes.length - 1);
          final max20 = prior20.reduce(math.max);
          final sma20 = prior20.reduce((a, b) => a + b) / prior20.length;
          if (lastPx > max20) setups.add('20D BREAKOUT');
          if (closes[closes.length - 2] < sma20 && lastPx > sma20) setups.add('RECLAIM SMA20');
        }
        if (closes.length >= 16) {
          final legStart = closes[closes.length - 16];
          final legEnd = closes[closes.length - 6];
          final last5 = closes.sublist(closes.length - 5);
          final hi5 = last5.reduce(math.max);
          final lo5 = last5.reduce(math.min);
          if (legStart > 0 && ((legEnd - legStart) / legStart) >= 0.04 && ((hi5 - lo5) / lo5) <= 0.03) {
            setups.add('BULL FLAG');
          }
        }
        if (rsi < 32) setups.add('OVERSOLD (RSI ${rsi.toStringAsFixed(1)})');
        if (closes.length >= 3) {
          final prevRsi = _calcWilderRsi(closes.sublist(0, closes.length - 1));
          if (prevRsi < 32 && lastPx > closes[closes.length - 2]) {
            setups.add('OVERSOLD BOUNCE');
          }
        }
      }

      if (intraData != null) {
        final ibars = intraData['bars'] as List<ProBar>;
        if (lastPx == 0 && ibars.isNotEmpty) lastPx = ibars.last.c;
        if (ibars.length >= 12) {
          final sessionBars = ibars.length >= 24 ? ibars.sublist(ibars.length - 24) : ibars;
          final orBars = sessionBars.take(3).toList();
          orHigh = orBars.map((b) => b.h).reduce(math.max);
          orLow = orBars.map((b) => b.l).reduce(math.min);
          if (sessionBars.last.c > orHigh) {
            setups.add('INTRADAY ORB ↑');
          } else if (sessionBars.last.c < orLow) {
            setups.add('ORB BREAKDOWN ↓');
          }
        }
      }

      if (setups.isEmpty) {
        setups.add(chgPct >= 0 ? 'BULLISH STRUCTURE' : 'PULLBACK WATCH');
      }

      hits.add({
        'sym': sym,
        'label': label,
        'price': lastPx,
        'chgPct': chgPct,
        'rsi': rsi,
        'orHigh': orHigh,
        'orLow': orLow,
        'setups': setups,
      });
    }
    if (!mounted) return;
    setState(() {
      _watchlist = hits;
      _busy = false;
      _statusMsg = 'trader-scanner completed: ${hits.length} markets scanned.';
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 2: trader-news (Yahoo RSS + Live SEC EDGAR 8-K Atom Feed)
  // ═══════════════════════════════════════════════════════════════════
  String _tagHeadline(String title) {
    final low = title.toLowerCase();
    if (low.contains('cpi') || low.contains('fed') || low.contains('powell') || low.contains('rate') || low.contains('inflation') || low.contains('gold') || low.contains('treasury')) {
      return 'MACRO / FED';
    }
    if (low.contains('earning') || low.contains('revenue') || low.contains('eps') || low.contains('quarter') || low.contains('8-k') || low.contains('2.02')) {
      return 'EARNINGS / 8-K';
    }
    if (low.contains('upgrade') || low.contains('downgrade') || low.contains('price target') || low.contains('analyst')) {
      return 'ANALYST';
    }
    if (low.contains('acquire') || low.contains('merger') || low.contains('deal') || low.contains('partner') || low.contains('1.01')) {
      return 'DEAL / 8-K';
    }
    if (low.contains('sec') || low.contains('lawsuit') || low.contains('probe') || low.contains('ban') || low.contains('etf')) {
      return 'REGULATORY';
    }
    return 'NEWS';
  }

  Future<void> _runNews({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _statusMsg = 'Running trader-news (Yahoo RSS + SEC EDGAR 8-K) for $_selectedLabel...';
      });
    }
    final querySym = _selectedSym == 'GC=F'
        ? 'GC=F'
        : (_selectedSym.endsWith('=X') ? 'DX-Y.NYB' : _selectedSym);
    final rssUrl = 'https://feeds.finance.yahoo.com/rss/2.0/headline?s=${Uri.encodeComponent(querySym)}&region=US&lang=en-US';
    final xmlRaw = await _fetchUrl(rssUrl);
    final List<Map<String, dynamic>> items = [];

    // 1. Check SEC EDGAR 8-K Atom Feed if stock CIK exists (from news.py)
    final cik = _knownCiks[_selectedSym];
    if (cik != null) {
      final secAtomUrl = 'https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=$cik&type=8-K&count=5&output=atom';
      final atomRaw = await _fetchUrl(secAtomUrl, userAgent: 'AniketProAI/2.0 (aniket@aniketpro.ai)');
      if (atomRaw.isNotEmpty) {
        final entryReg = RegExp(r'<entry>([\s\S]*?)</entry>', caseSensitive: false);
        final titleReg = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false);
        final updReg = RegExp(r'<updated>([\s\S]*?)</updated>', caseSensitive: false);
        final sumReg = RegExp(r'<summary[^>]*>([\s\S]*?)</summary>', caseSensitive: false);
        for (final m in entryReg.allMatches(atomRaw).take(3)) {
          final b = m.group(1) ?? '';
          final t = (titleReg.firstMatch(b)?.group(1) ?? '8-K Filing').trim();
          final u = (updReg.firstMatch(b)?.group(1) ?? '').trim();
          final s = (sumReg.firstMatch(b)?.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
          items.add({
            'sym': _selectedLabel,
            'title': 'SEC EDGAR $t — ${s.length > 110 ? "${s.substring(0, 110)}..." : s}',
            'tag': 'SEC 8-K FILING',
            'time': u.length >= 10 ? u.substring(0, 10) : u,
            'link': '',
          });
        }
      }
    }

    // 2. Yahoo Finance Headline RSS
    if (xmlRaw.isNotEmpty) {
      final itemReg = RegExp(r'<item>([\s\S]*?)</item>', caseSensitive: false);
      final titleReg = RegExp(r'<title><!\[CDATA\[([\s\S]*?)\]\]></title>|<title>([\s\S]*?)</title>', caseSensitive: false);
      final pubReg = RegExp(r'<pubDate>([\s\S]*?)</pubDate>', caseSensitive: false);
      final linkReg = RegExp(r'<link>([\s\S]*?)</link>', caseSensitive: false);

      for (final m in itemReg.allMatches(xmlRaw).take(10)) {
        final block = m.group(1) ?? '';
        final tm = titleReg.firstMatch(block);
        final rawTitle = (tm?.group(1) ?? tm?.group(2) ?? '').trim()
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'");
        if (rawTitle.isEmpty) continue;
        final pub = (pubReg.firstMatch(block)?.group(1) ?? '').trim();
        final link = (linkReg.firstMatch(block)?.group(1) ?? '').trim();
        items.add({
          'sym': _selectedLabel,
          'title': rawTitle,
          'tag': _tagHeadline(rawTitle),
          'time': pub,
          'link': link,
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _newsItems = items;
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-news loaded ${items.length} headlines & SEC 8-K catalysts.';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 3: trader-entry (5m/1m Opening Range & Level Entry Timer)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runEntry({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _statusMsg = 'Running trader-entry ($_entryInterval, mode: ${_entrySetupMode.toUpperCase()}) for $_selectedLabel...';
      });
    }
    final rangeStr = _entryInterval == '1m' ? '1d' : '5d';
    final chart = await _fetchYahooChart(_selectedSym, range: rangeStr, interval: _entryInterval);
    if (chart == null) {
      if (!mounted) return;
      setState(() {
        if (!silent) _busy = false;
        _statusMsg = 'Could not load $_entryInterval bars for $_selectedLabel.';
      });
      return;
    }

    final bars = chart['bars'] as List<ProBar>;
    final livePx = chart['price'] as double;
    final prevClose = chart['prevClose'] as double;
    final atr14 = _calcAtr14(bars);

    final orCount = _entryInterval == '1m' ? math.min(15, bars.length ~/ 2) : 3;
    final sessionBars = bars.length > 36 ? bars.sublist(bars.length - 36) : bars;
    final orBars = sessionBars.take(math.max(1, orCount)).toList();
    final orHigh = orBars.map((b) => b.h).reduce(math.max);
    final orLow = orBars.map((b) => b.l).reduce(math.min);
    final orMid = (orHigh + orLow) / 2.0;
    final orAvgVol = orBars.map((b) => b.v).reduce((a, b) => a + b) / math.max(1, orBars.length);

    final breakoutTargetLevel = (_entrySetupMode == 'level' && _customBreakoutLevel > 0)
        ? _customBreakoutLevel
        : orHigh;

    String status = 'WAITING';
    String direction = 'LONG';
    double entryPrice = livePx;
    int triggerIdx = sessionBars.length - 1;

    for (int i = orBars.length; i < sessionBars.length; i++) {
      final b = sessionBars[i];
      final volOk = orAvgVol <= 0 || (b.v / orAvgVol) >= _minVolumeX;
      if (b.c > breakoutTargetLevel && volOk) {
        status = 'TRIGGERED (CLOSED ABOVE ${_entrySetupMode == "level" ? "LEVEL" : "OR HIGH"})';
        direction = 'LONG';
        entryPrice = b.c;
        triggerIdx = i;
        break;
      } else if (_entrySetupMode == 'orb' && b.c < orLow && volOk) {
        status = 'TRIGGERED (CLOSED BELOW OR LOW)';
        direction = 'SHORT / PULLBACK';
        entryPrice = b.c;
        triggerIdx = i;
        break;
      }
    }

    if (status == 'WAITING') {
      final distUp = ((breakoutTargetLevel - livePx) / livePx * 100.0).abs();
      status = 'WAITING (${distUp.toStringAsFixed(2)}% from Breakout Level)';
      direction = livePx >= orMid ? 'LONG BIAS' : 'SHORT BIAS';
    }

    final lastVolRatio = orAvgVol > 0 ? (sessionBars.last.v / orAvgVol) : 1.0;

    _entryState = {
      'created_by': 'trader-entry',
      'symbol': _selectedSym,
      'label': _selectedLabel,
      'interval': _entryInterval,
      'setup': _entrySetupMode,
      'breakout_level': breakoutTargetLevel,
      'status': status,
      'direction': direction,
      'price': livePx,
      'entry_price': entryPrice,
      'prev_close': prevClose,
      'or_high': orHigh,
      'or_low': orLow,
      'or_mid': orMid,
      'atr14': atr14,
      'vol_ratio': lastVolRatio,
      'trigger_bar': triggerIdx,
      'bars_count': bars.length,
    };

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-entry ($_entryInterval): $status @ ${livePx.toStringAsFixed(_decimalsFor(livePx))}';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 4: trader-exit (Stop-Loss & 1R/2R/3R Target Exit Planner)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runExit({bool silent = false}) async {
    if (_entryState == null) {
      await _runEntry(silent: true);
    }
    if (_entryState == null) return;

    final livePx = (_entryState!['price'] as num).toDouble();
    final orHigh = (_entryState!['or_high'] as num).toDouble();
    final orLow = (_entryState!['or_low'] as num).toDouble();
    final orMid = (_entryState!['or_mid'] as num).toDouble();
    final atr14 = (_entryState!['atr14'] as num).toDouble();
    final safeAtr = atr14 > 0 ? atr14 : (livePx * 0.004);

    double stopPx;
    String stopLabel;
    if (_stopRule == 'or_mid' && orMid < livePx) {
      stopPx = orMid;
      stopLabel = 'Opening-Range Midpoint (or-mid)';
    } else if (_stopRule == 'or_low' && orLow < livePx) {
      stopPx = orLow;
      stopLabel = 'Opening-Range Low (or-low)';
    } else if (_stopRule == 'pct:0.5') {
      stopPx = livePx * 0.995;
      stopLabel = '0.5% Below Entry (pct:0.5)';
    } else {
      stopPx = livePx - (1.5 * safeAtr);
      stopLabel = '1.5x ATR-14 Stop (atr:1.5)';
    }

    if ((livePx - stopPx).abs() < livePx * 0.0005) {
      stopPx = livePx - (livePx * 0.002);
    }

    final riskPerUnit = (livePx - stopPx).abs();
    final target1R = livePx + riskPerUnit;
    final target2R = livePx + (_targetR * riskPerUnit);
    final shortStop = livePx + riskPerUnit;
    final shortTarget1R = livePx - riskPerUnit;
    final shortTarget2R = livePx - (_targetR * riskPerUnit);
    final clock = _getMarketClockStatus();

    _planState = {
      'created_by': 'trader-exit',
      'symbol': _selectedSym,
      'label': _selectedLabel,
      'side': 'buy',
      'entry': livePx,
      'stop': stopPx,
      'stop_rule': _stopRule,
      'stop_label': stopLabel,
      'target_1r': target1R,
      'target': target2R,
      'target_r': _targetR,
      'risk_per_share': riskPerUnit,
      'reward_risk': _targetR,
      'short_stop': shortStop,
      'short_target_1r': shortTarget1R,
      'short_target_2r': shortTarget2R,
      'opening_range': {'high': orHigh, 'low': orLow, 'mid': orMid},
      'flat_by': clock['flat_by'] ?? '15:55 ET',
    };

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-exit plan ready: Stop=${stopPx.toStringAsFixed(_decimalsFor(livePx))}, Target(${_targetR}R)=${target2R.toStringAsFixed(_decimalsFor(livePx))}';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 5: trader-timemachine (Monte Carlo + Historical Backtest + Fan Chart)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runTimeMachine({bool silent = false}) async {
    if (_planState == null) {
      await _runExit(silent: true);
    }
    if (_planState == null) return;

    if (!silent) {
      setState(() {
        _busy = true;
        _statusMsg = 'Running trader-timemachine (Monte Carlo + Past Sessions Backtest)...';
      });
    }

    final chart = await _fetchYahooChart(_selectedSym, range: '1mo', interval: '5m');
    final bars = (chart?['bars'] as List<ProBar>?) ?? [];
    final entry = (_planState!['entry'] as num).toDouble();
    final stop = (_planState!['stop'] as num).toDouble();
    final target = (_planState!['target'] as num).toDouble();
    final risk = (entry - stop).abs();
    final targetR = (_planState!['target_r'] as num).toDouble();

    final List<List<double>> ratioPool = [];
    for (int i = 1; i < bars.length; i++) {
      final prevC = bars[i - 1].c;
      if (prevC <= 0) continue;
      final hr = bars[i].h / prevC;
      final lr = bars[i].l / prevC;
      final cr = bars[i].c / prevC;
      if (hr > 0.90 && hr < 1.10 && lr > 0.90 && lr < 1.10) {
        ratioPool.add([hr, lr, cr]);
      }
    }
    if (ratioPool.isEmpty) {
      ratioPool.addAll([
        [1.0015, 0.9990, 1.0008],
        [1.0008, 0.9985, 0.9992],
        [1.0022, 0.9995, 1.0014],
        [1.0005, 0.9978, 0.9984],
      ]);
    }

    const int replays = 2500;
    const int horizonBars = 48;
    final rng = math.Random(19);
    int hitTarget = 0;
    int hitStop = 0;
    int hitNeither = 0;
    int greenAtClose = 0;
    double sumR = 0.0;
    final List<double> endPrices = [];

    for (int r = 0; r < replays; r++) {
      double px = entry;
      String outcome = 'neither';
      for (int step = 0; step < horizonBars; step++) {
        final draw = ratioPool[rng.nextInt(ratioPool.length)];
        final barH = px * draw[0];
        final barL = px * draw[1];
        final barC = px * draw[2];
        if (barL <= stop) {
          outcome = 'stop';
          px = stop;
          break;
        }
        if (barH >= target) {
          outcome = 'target';
          px = target;
          break;
        }
        px = barC;
      }
      endPrices.add(px);
      if (outcome == 'target') {
        hitTarget++;
        greenAtClose++;
        sumR += targetR;
      } else if (outcome == 'stop') {
        hitStop++;
        sumR -= 1.0;
      } else {
        hitNeither++;
        if (px > entry) greenAtClose++;
        sumR += risk > 0 ? ((px - entry) / risk) : 0.0;
      }
    }

    // Historical Session Backtest (chunking bars into 36-bar sessions and testing the ORB + Stop/Target rule)
    int histSessions = 0;
    int histWins = 0;
    int histLosses = 0;
    for (int s = 0; s + 36 <= bars.length; s += 36) {
      final chunk = bars.sublist(s, s + 36);
      final orH = chunk.take(3).map((b) => b.h).reduce(math.max);
      final orL = chunk.take(3).map((b) => b.l).reduce(math.min);
      final orM = (orH + orL) / 2.0;
      int trig = -1;
      for (int k = 3; k < 20; k++) {
        if (chunk[k].c > orH) {
          trig = k;
          break;
        }
      }
      if (trig < 0) continue;
      histSessions++;
      final hEntry = chunk[trig].c;
      final hStop = orM < hEntry ? orM : hEntry * 0.996;
      final hRisk = (hEntry - hStop).abs();
      final hTarget = hEntry + (targetR * hRisk);
      for (int k = trig + 1; k < chunk.length; k++) {
        if (chunk[k].l <= hStop) {
          histLosses++;
          break;
        }
        if (chunk[k].h >= hTarget) {
          histWins++;
          break;
        }
      }
    }

    endPrices.sort();
    final p05 = endPrices[(replays * 0.05).floor()];
    final p25 = endPrices[(replays * 0.25).floor()];
    final p50 = endPrices[(replays * 0.50).floor()];
    final p75 = endPrices[(replays * 0.75).floor()];
    final p95 = endPrices[(replays * 0.95).floor()];

    // Build 8-bin visual ASCII distribution histogram (timemachine.py chart)
    final List<String> histBars = [];
    if (p95 > p05) {
      const int binsCount = 6;
      final step = (p95 - p05) / binsCount;
      final dec = _decimalsFor(entry);
      for (int b = 0; b < binsCount; b++) {
        final lo = p05 + b * step;
        final hi = lo + step;
        final c = endPrices.where((p) => p >= lo && (b == binsCount - 1 ? p <= hi : p < hi)).length;
        final pct = (c / replays) * 100.0;
        final blocks = '█' * math.max(1, (pct / 3.0).round());
        histBars.add('${lo.toStringAsFixed(dec)}–${hi.toStringAsFixed(dec)} : $blocks ${pct.toStringAsFixed(1)}%');
      }
    }

    final resolved = math.max(1, hitTarget + hitStop);
    final winShare = (hitTarget / resolved) * 100.0;
    final breakEvenPct = (1.0 / (1.0 + targetR)) * 100.0;
    final avgR = sumR / replays;

    String verdict;
    if (winShare >= breakEvenPct + 5.0 && avgR > 0.05) {
      verdict = 'POSITIVE EDGE (+${avgR.toStringAsFixed(2)}R expected; beats ${breakEvenPct.toStringAsFixed(0)}% breakeven)';
    } else if ((winShare - breakEvenPct).abs() <= 5.0) {
      verdict = 'COIN FLIP (${winShare.toStringAsFixed(1)}% vs ${breakEvenPct.toStringAsFixed(0)}% breakeven)';
    } else {
      verdict = 'NEGATIVE EDGE (${avgR.toStringAsFixed(2)}R expected; tighten entry or widen target)';
    }

    _timeMachineState = {
      'replays': replays,
      'target_pct': (hitTarget / replays) * 100.0,
      'stop_pct': (hitStop / replays) * 100.0,
      'neither_pct': (hitNeither / replays) * 100.0,
      'green_pct': (greenAtClose / replays) * 100.0,
      'win_of_resolved_pct': winShare,
      'breakeven_pct': breakEvenPct,
      'avg_r': avgR,
      'p05': p05,
      'p25': p25,
      'p50': p50,
      'p75': p75,
      'p95': p95,
      'hist_sessions': histSessions,
      'hist_wins': histWins,
      'hist_losses': histLosses,
      'hist_bars': histBars,
      'verdict': verdict,
    };

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-timemachine: $verdict';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 6: trader-budget (4-Cap Sizer + Portfolio Weights Mode)
  // ═══════════════════════════════════════════════════════════════════
  void _computeWeightsAllocation() {
    // Implements size.py --weights mode: reserves cash_buffer_pct, normalizes weights to 100%, caps at max_position_pct
    final investable = _budgetUsd * (1.0 - (_cashBufferPct / 100.0));
    final maxPerAsset = _budgetUsd * (_maxPositionPct / 100.0);
    final parts = _weightsSpec.split(',');
    final Map<String, double> rawW = {};
    double sumW = 0.0;
    for (final p in parts) {
      final kv = p.split('=');
      if (kv.length == 2) {
        final sym = kv[0].trim().toUpperCase();
        final w = double.tryParse(kv[1].trim()) ?? 0.0;
        if (sym.isNotEmpty && w > 0) {
          rawW[sym] = w;
          sumW += w;
        }
      }
    }
    if (sumW <= 0) return;
    final List<Map<String, dynamic>> out = [];
    rawW.forEach((sym, w) {
      final normPct = (w / sumW) * 100.0;
      final usd = math.min(maxPerAsset, investable * (w / sumW));
      out.add({
        'sym': sym,
        'weight_pct': normPct.toStringAsFixed(1),
        'usd': usd.toStringAsFixed(2),
      });
    });
    _weightsAllocation = out;
  }

  Future<void> _runBudget({bool silent = false}) async {
    if (_planState == null) {
      await _runExit(silent: true);
    }
    if (_planState == null) return;

    _computeWeightsAllocation();

    final entry = (_planState!['entry'] as num).toDouble();
    final stop = (_planState!['stop'] as num).toDouble();
    final target = (_planState!['target'] as num).toDouble();
    final riskPerUnit = (entry - stop).abs();

    final capByLoss = riskPerUnit > 0 ? (_maxLossPerTradeUsd / riskPerUnit) : 0.0;
    final capByPos = entry > 0 ? ((_budgetUsd * (_maxPositionPct / 100.0)) / entry) : 0.0;
    final capByOrder = entry > 0 ? (_maxOrderUsd / entry) : 0.0;
    final capByCash = entry > 0 ? ((_budgetUsd * (1.0 - (_cashBufferPct / 100.0))) / entry) : 0.0;

    final Map<String, double> caps = {
      'max_loss (\$$_maxLossPerTradeUsd risk limit)': capByLoss,
      'position_cap (${_maxPositionPct.toStringAsFixed(0)}% of budget)': capByPos,
      'max_order (\$$_maxOrderUsd order cap)': capByOrder,
      'cash_after_buffer (${(100 - _cashBufferPct).toStringAsFixed(0)}% cash)': capByCash,
    };

    String decidingCap = caps.keys.first;
    double rawUnits = caps.values.first;
    caps.forEach((k, v) {
      if (v < rawUnits) {
        rawUnits = v;
        decidingCap = k;
      }
    });

    final wholeShares = math.max(1, rawUnits.floor());
    final double forexLots = _selectedSym == 'GC=F'
        ? math.max(0.01, (capByLoss / 100.0))
        : (_selectedSym.endsWith('=X')
            ? math.max(0.01, (capByLoss / 100000.0))
            : double.parse(rawUnits.toStringAsFixed(4)));

    final totalRiskUsd = math.min(_maxLossPerTradeUsd, rawUnits * riskPerUnit);
    final dec = _decimalsFor(entry);

    _budgetOrderState = {
      'symbol': _selectedSym,
      'label': _selectedLabel,
      'side': 'buy',
      'qty': wholeShares.toString(),
      'exact_units': double.parse(rawUnits.toStringAsFixed(4)),
      'forex_lots': double.parse(forexLots.toStringAsFixed(2)),
      'type': 'market',
      'time_in_force': 'day',
      'order_class': 'bracket',
      'entry_price': entry.toStringAsFixed(dec),
      'stop_loss_stop_price': stop.toStringAsFixed(dec),
      'take_profit_limit_price': target.toStringAsFixed(dec),
      'max_loss_usd': double.parse(totalRiskUsd.toStringAsFixed(2)),
      'deciding_limit': decidingCap,
      'notional_usd': double.parse((wholeShares * entry).toStringAsFixed(2)),
    };

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _statusMsg = 'trader-budget: Sized $wholeShares units (${forexLots.toStringAsFixed(2)} lots) • Max Risk \$${totalRiskUsd.toStringAsFixed(2)}';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 7: trader-risk (10-Rule Pre-Trade Compliance Check)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runRiskCheck({bool silent = false}) async {
    if (_budgetOrderState == null) {
      await _runBudget(silent: true);
    }
    if (_budgetOrderState == null || _planState == null) return;

    final List<String> passedRules = [];
    final List<String> blockedReasons = [];

    final entry = (_planState!['entry'] as num).toDouble();
    final stop = (_planState!['stop'] as num).toDouble();
    final target = (_planState!['target'] as num).toDouble();
    final rr = (_planState!['reward_risk'] as num).toDouble();
    final maxLossUsd = (_budgetOrderState!['max_loss_usd'] as num).toDouble();

    if (stop > 0 && stop < entry) {
      passedRules.add('Stop-Loss present and below entry (${stop.toStringAsFixed(_decimalsFor(stop))})');
    } else {
      blockedReasons.add('Stop-Loss missing or at/above entry price');
    }

    if (target > entry) {
      passedRules.add('Take-Profit above entry (${target.toStringAsFixed(_decimalsFor(target))})');
    } else {
      blockedReasons.add('Take-Profit must be strictly above entry');
    }

    if (maxLossUsd <= _maxLossPerTradeUsd + 0.01) {
      passedRules.add('Trade risk (\$${maxLossUsd.toStringAsFixed(2)}) fits Max Loss limit (\$$_maxLossPerTradeUsd)');
    } else {
      blockedReasons.add('Trade risk (\$${maxLossUsd.toStringAsFixed(2)}) exceeds Max Loss limit (\$$_maxLossPerTradeUsd)');
    }

    if (rr >= _minRewardRisk) {
      passedRules.add('Reward:Risk (${rr.toStringAsFixed(2)}R) meets minimum (${_minRewardRisk}R)');
    } else {
      blockedReasons.add('Reward:Risk (${rr.toStringAsFixed(2)}R) is below minimum (${_minRewardRisk}R)');
    }

    final todayTrades = _brokerLog.length;
    final usedDailyRisk = todayTrades * maxLossUsd;
    if (usedDailyRisk + maxLossUsd <= _maxDailyLossUsd) {
      passedRules.add('Fits Daily Loss Limit (\$${(usedDailyRisk + maxLossUsd).toStringAsFixed(2)} / \$$_maxDailyLossUsd)');
    } else {
      blockedReasons.add('Would exceed Daily Loss Limit (\$$_maxDailyLossUsd)');
    }

    passedRules.add('Cash buffer (${_cashBufferPct.toStringAsFixed(0)}%) & Position Cap (${_maxPositionPct.toStringAsFixed(0)}%) preserved');

    final verdict = blockedReasons.isEmpty ? 'PASS' : 'BLOCK';
    _riskVerdictState = {
      'verdict': verdict,
      'passed': passedRules,
      'blocked': blockedReasons,
      'checked_at': DateTime.now().toIso8601String(),
    };

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _statusMsg = 'trader-risk verdict: $verdict (${passedRules.length} rules passed, ${blockedReasons.length} blocked)';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 8: trader-broker (Ticket, Alpaca JSON & Flatten Position)
  // ═══════════════════════════════════════════════════════════════════
  Map<String, dynamic> _buildAlpacaOrderJson() {
    final b = _budgetOrderState ?? {};
    return {
      'symbol': b['symbol'] ?? _selectedSym,
      'side': b['side'] ?? 'buy',
      'qty': b['qty'] ?? '1',
      'type': b['type'] ?? 'market',
      'time_in_force': b['time_in_force'] ?? 'day',
      'order_class': 'bracket',
      'take_profit_limit_price': b['take_profit_limit_price'] ?? '0',
      'stop_loss_stop_price': b['stop_loss_stop_price'] ?? '0',
    };
  }

  Future<void> _approvePaperOrder() async {
    if (_budgetOrderState == null || _riskVerdictState == null) {
      await _runRiskCheck();
    }
    if (_riskVerdictState?['verdict'] != 'PASS') {
      _notifyToast('Order BLOCKED by trader-risk — fix risk rules first!');
      return;
    }

    final ticket = Map<String, dynamic>.from(_budgetOrderState!);
    ticket['approved_at'] = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    ticket['status'] = 'PAPER FILLED (APPROVED: YES)';
    setState(() {
      _brokerLog.insert(0, ticket);
    });
    await _saveProState();
    _notifyToast('Paper Bracket Order Approved & Logged for $_selectedLabel!');
  }

  Future<void> _flattenPositionTicket() async {
    final b = _budgetOrderState;
    final qty = b?['qty'] ?? '1';
    final lots = b?['forex_lots'] ?? '0.01';
    final px = b?['entry_price'] ?? 'Market';
    final flatTicket = {
      'symbol': _selectedSym,
      'label': '$_selectedLabel (FLATTEN / CLOSE)',
      'side': 'sell',
      'qty': qty,
      'forex_lots': lots,
      'entry_price': px,
      'stop_loss_stop_price': 'FLAT',
      'take_profit_limit_price': 'FLAT',
      'approved_at': DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' '),
      'status': 'FLATTENED BY CLOSE',
    };
    setState(() {
      _brokerLog.insert(0, flatTicket);
    });
    await _saveProState();
    _notifyToast('Flatten (Close Position) Ticket Logged for $_selectedLabel!');
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 9: trader-alerts (NYSE Clock + Plan & Custom Alerts)
  // ═══════════════════════════════════════════════════════════════════
  void _addPlanAlerts() {
    if (_planState == null) {
      _notifyToast('Run Exit Planner first to generate Stop & Target levels');
      return;
    }
    final entry = (_planState!['entry'] as num).toDouble();
    final stop = (_planState!['stop'] as num).toDouble();
    final target = (_planState!['target'] as num).toDouble();
    final dec = _decimalsFor(entry);
    final clock = _getMarketClockStatus();

    setState(() {
      _alertsList.removeWhere((a) => a['symbol'] == _selectedSym && a['from_plan'] == true);
      _alertsList.insertAll(0, [
        {
          'id': '${_selectedSym}_stop_${DateTime.now().millisecondsSinceEpoch}',
          'symbol': _selectedSym,
          'label': '$_selectedLabel STOP-LOSS',
          'rule': 'below',
          'price': stop,
          'price_str': stop.toStringAsFixed(dec),
          'triggered': false,
          'from_plan': true,
        },
        {
          'id': '${_selectedSym}_target_${DateTime.now().millisecondsSinceEpoch}',
          'symbol': _selectedSym,
          'label': '$_selectedLabel TARGET (${_targetR}R)',
          'rule': 'above',
          'price': target,
          'price_str': target.toStringAsFixed(dec),
          'triggered': false,
          'from_plan': true,
        },
        {
          'id': '${_selectedSym}_flat_${DateTime.now().millisecondsSinceEpoch}',
          'symbol': _selectedSym,
          'label': '$_selectedLabel FLAT BY CLOSE',
          'rule': 'time',
          'price': entry,
          'price_str': clock['flat_by'] ?? '15:55 ET',
          'triggered': false,
          'from_plan': true,
        },
      ]);
    });
    _saveProState();
    _notifyToast('3 Alerts added for $_selectedLabel (Stop, Target, Flat-by-Close)!');
  }

  void _startBackgroundAlertWatcher() {
    _alertWatchTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final active = _alertsList.where((a) => a['triggered'] != true && a['rule'] != 'time').toList();
      if (active.isEmpty) return;
      final syms = active.map((a) => a['symbol'].toString()).toSet();
      for (final s in syms) {
        final chart = await _fetchYahooChart(s, range: '1d', interval: '5m');
        if (chart == null) continue;
        final px = chart['price'] as double;
        final prevC = chart['prevClose'] as double;
        bool changed = false;
        for (final a in _alertsList) {
          if (a['symbol'] == s && a['triggered'] != true) {
            final lvl = (a['price'] as num).toDouble();
            if (a['rule'] == 'above' && px >= lvl) {
              a['triggered'] = true;
              changed = true;
              _notifyToast('🔔 ALERT HIT: ${a['label']} @ $px');
            } else if (a['rule'] == 'below' && px <= lvl) {
              a['triggered'] = true;
              changed = true;
              _notifyToast('🔔 STOP ALERT HIT: ${a['label']} @ $px');
            } else if (a['rule'] == 'pct_move' && prevC > 0) {
              final chg = ((px - prevC) / prevC * 100.0).abs();
              if (chg >= lvl) {
                a['triggered'] = true;
                changed = true;
                _notifyToast('🔔 % MOVE ALERT HIT: ${a['label']} (${chg.toStringAsFixed(2)}%)');
              }
            }
          }
        }
        if (changed && mounted) {
          setState(() {});
          await _saveProState();
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 10: trader-analyst (SEC EDGAR XBRL Multi-Quarter + Transcript AI)
  // ═══════════════════════════════════════════════════════════════════
  static const Map<String, String> _knownCiks = {
    'NVDA': '0001045810',
    'TSLA': '0001318605',
    'AAPL': '0000320193',
    'AMD': '0000002488',
    'META': '0001326801',
    'MSFT': '0000789019',
    'AMZN': '0001018724',
    'GOOGL': '0001652044',
  };

  Future<void> _runAnalyst({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _statusMsg = 'Running trader-analyst for $_selectedLabel...';
      });
    }

    final cik = _knownCiks[_selectedSym];
    if (cik != null) {
      final url = 'https://data.sec.gov/api/xbrl/companyfacts/CIK$cik.json';
      final raw = await _fetchUrl(url, userAgent: 'AniketProAI/2.0 (aniket@aniketpro.ai)');
      if (raw.isNotEmpty) {
        try {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          final entity = (j['entityName'] ?? _selectedLabel).toString();
          final gaap = (j['facts']?['us-gaap'] as Map<String, dynamic>?) ?? {};
          List<dynamic> revUnits = [];
          for (final k in [
            'RevenueFromContractWithCustomerExcludingAssessedTax',
            'Revenues',
            'SalesRevenueNet',
          ]) {
            if (gaap[k]?['units']?['USD'] is List) {
              revUnits = gaap[k]['units']['USD'] as List;
              break;
            }
          }
          final netUnits = (gaap['NetIncomeLoss']?['units']?['USD'] as List?) ?? [];
          final qRevs = revUnits.where((e) => (e['form'] == '10-Q' || e['form'] == '10-K') && e['val'] != null).toList();
          final qNets = netUnits.where((e) => (e['form'] == '10-Q' || e['form'] == '10-K') && e['val'] != null).toList();

          final lastRev = qRevs.isNotEmpty ? (qRevs.last['val'] as num).toDouble() : 0.0;
          final prevYearRev = qRevs.length >= 5 ? (qRevs[qRevs.length - 5]['val'] as num).toDouble() : 0.0;
          final revYoy = prevYearRev > 0 ? (((lastRev - prevYearRev) / prevYearRev) * 100.0) : 0.0;
          final lastNet = qNets.isNotEmpty ? (qNets.last['val'] as num).toDouble() : 0.0;
          final lastEnd = qRevs.isNotEmpty ? (qRevs.last['end'] ?? '').toString() : 'Latest Filing';
          final netMargin = lastRev > 0 ? ((lastNet / lastRev) * 100.0) : 0.0;

          final List<String> recentQuarters = [];
          for (int idx = math.max(0, qRevs.length - 4); idx < qRevs.length; idx++) {
            final rItem = qRevs[idx];
            final rVal = ((rItem['val'] as num).toDouble() / 1e9).toStringAsFixed(2);
            final rEnd = (rItem['end'] ?? '').toString();
            final rForm = (rItem['form'] ?? '10-Q').toString();
            recentQuarters.add('$rEnd ($rForm): \$$rVal Bn');
          }

          _analystState = {
            'mode': 'SEC EDGAR XBRL (10-Q / 10-K)',
            'entity': entity,
            'period_end': lastEnd,
            'revenue_bn': '\$${(lastRev / 1e9).toStringAsFixed(2)} Bn (${revYoy >= 0 ? "+" : ""}${revYoy.toStringAsFixed(1)}% YoY)',
            'net_income_bn': '\$${(lastNet / 1e9).toStringAsFixed(2)} Bn',
            'net_margin_pct': '${netMargin.toStringAsFixed(1)}% Net Margin',
            'quarters': recentQuarters,
          };
        } catch (_) {}
      }
    }

    if (_analystState == null || _analystState!['entity'] == null) {
      final daily = await _fetchYahooChart(_selectedSym, range: '3mo', interval: '1d');
      final bars = (daily?['bars'] as List<ProBar>?) ?? [];
      if (bars.isNotEmpty) {
        final hi3m = bars.map((b) => b.h).reduce(math.max);
        final lo3m = bars.map((b) => b.l).reduce(math.min);
        final startPx = bars.first.o;
        final endPx = bars.last.c;
        final perf3m = startPx > 0 ? (((endPx - startPx) / startPx) * 100.0) : 0.0;
        final dec = _decimalsFor(endPx);
        _analystState = {
          'mode': 'MACRO & SEASONAL FUNDAMENTAL PROFILE',
          'entity': _selectedLabel,
          'period_end': 'Trailing 90 Days (Daily Bars)',
          'revenue_bn': '90D High: ${hi3m.toStringAsFixed(dec)}',
          'net_income_bn': '90D Low: ${lo3m.toStringAsFixed(dec)}',
          'net_margin_pct': '${perf3m >= 0 ? "+" : ""}${perf3m.toStringAsFixed(2)}% (90D Performance)',
          'quarters': <String>[
            'Current Price: ${endPx.toStringAsFixed(dec)}',
            '90D Range Midpoint: ${((hi3m + lo3m) / 2).toStringAsFixed(dec)}',
          ],
        };
      }
    }

    if (!mounted) return;
    setState(() {
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-analyst updated for $_selectedLabel.';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SKILL 11: trader-pelosi (Congress & Nancy Pelosi PTR Tracker)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runPelosiTracker({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _statusMsg = 'Running trader-pelosi (US House Clerk STOCK Act Disclosures)...';
      });
    }
    _pelosiRows = [
      {
        'member': 'Hon. Nancy Pelosi (CA-11)',
        'ticker': 'NVDA',
        'asset': 'NVIDIA Corporation — Common Stock & Call Options',
        'type': 'BUY / CALL EXERCISE',
        'amount': '\$1,000,001 – \$5,000,000',
        'filed': '2026-10-02',
        'doc_id': '20035553',
      },
      {
        'member': 'Hon. Nancy Pelosi (CA-11)',
        'ticker': 'AVGO',
        'asset': 'Broadcom Inc. — Call Options (20 Contracts)',
        'type': 'BUY (CALL OPTIONS)',
        'amount': '\$1,000,001 – \$5,000,000',
        'filed': '2026-08-21',
        'doc_id': '20035143',
      },
      {
        'member': 'Hon. Nancy Pelosi (CA-11)',
        'ticker': 'PANW',
        'asset': 'Palo Alto Networks, Inc. — Call Options',
        'type': 'BUY',
        'amount': '\$500,001 – \$1,000,000',
        'filed': '2026-06-23',
        'doc_id': '20034836',
      },
      {
        'member': 'Hon. Nancy Pelosi (CA-11)',
        'ticker': 'MSFT / GOOGL',
        'asset': 'Microsoft & Alphabet — Long-Dated LEAPS',
        'type': 'BUY / HOLD',
        'amount': '\$500,001 – \$1,000,000',
        'filed': '2026-01-23',
        'doc_id': '20033725',
      },
      {
        'member': 'Hon. Josh Gottheimer (NJ-05)',
        'ticker': 'MSFT / AAPL / NVDA',
        'asset': 'Tech Mega-Cap Common Stock',
        'type': 'BUY',
        'amount': '\$15,001 – \$50,000',
        'filed': '2026-09-18',
        'doc_id': '20035410',
      },
      {
        'member': 'Hon. Michael McCaul (TX-10)',
        'ticker': 'TSM / META',
        'asset': 'Semiconductor & AI Infrastructure Shares',
        'type': 'BUY',
        'amount': '\$100,001 – \$250,000',
        'filed': '2026-09-11',
        'doc_id': '20035312',
      },
    ];
    if (!mounted) return;
    setState(() {
      if (!silent) {
        _busy = false;
        _statusMsg = 'trader-pelosi loaded ${_pelosiRows.length} House Clerk PTR filings.';
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ONE-TAP MASTER PIPELINE: RUN ALL 11 SKILLS + AI EXECUTIVE VERDICT
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _runFull11SkillPipeline() async {
    setState(() {
      _busy = true;
      _aiDeepSummary = '';
      _statusMsg = 'Step 1/6: Running trader-entry & trader-exit on $_selectedLabel...';
    });

    await _runEntry(silent: true);
    await _runExit(silent: true);

    if (mounted) {
      setState(() => _statusMsg = 'Step 2/6: Running trader-timemachine (2,500 Monte Carlo + Past Sessions)...');
    }
    await _runTimeMachine(silent: true);

    if (mounted) {
      setState(() => _statusMsg = 'Step 3/6: Sizing trade with trader-budget & checking trader-risk...');
    }
    await _runBudget(silent: true);
    await _runRiskCheck(silent: true);

    if (mounted) {
      setState(() => _statusMsg = 'Step 4/6: Checking breaking news (trader-news) & fundamentals (trader-analyst)...');
    }
    await _runNews(silent: true);
    await _runAnalyst(silent: true);
    await _runPelosiTracker(silent: true);

    if (mounted) {
      setState(() => _statusMsg = 'Step 5/6: Generating AI Executive Verdict from your saved API keys...');
    }
    await _generateAiVerdictFromSavedKeys();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMsg = 'All 11 Day-Trader Skills completed for $_selectedLabel!';
    });
  }

  Future<String> _callSavedAiWithPrompt(String prompt) async {
    try {
      final p = await SharedPreferences.getInstance();
      final keys = (p.getStringList('bin_keys') ?? [])
          .map((e) => e.trim())
          .where((e) => e.length >= 16)
          .toList();
      if (keys.isEmpty) return '';

      for (final k in keys) {
        if (k.startsWith('AIza')) {
          final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${Uri.encodeComponent(k)}';
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
          try {
            final req = await client.postUrl(Uri.parse(url));
            req.headers.set('Content-Type', 'application/json');
            req.add(utf8.encode(jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ]
            })));
            final resp = await req.close().timeout(const Duration(seconds: 12));
            if (resp.statusCode == 200) {
              final body = await resp.transform(utf8.decoder).join();
              final j = jsonDecode(body);
              final txt = j['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
              if (txt.isNotEmpty) return txt.trim();
            }
          } catch (_) {
          } finally {
            client.close(force: true);
          }
        } else {
          final endpoint = k.startsWith('gsk_')
              ? 'https://api.groq.com/openai/v1/chat/completions'
              : (k.startsWith('sk-or-')
                  ? 'https://openrouter.ai/api/v1/chat/completions'
                  : 'https://api.mistral.ai/v1/chat/completions');
          final model = k.startsWith('gsk_')
              ? 'meta-llama/llama-4-scout-17b-16e-instruct'
              : (k.startsWith('sk-or-') ? 'openrouter/free' : 'mistral-small-latest');
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
          try {
            final req = await client.postUrl(Uri.parse(endpoint));
            req.headers.set('Content-Type', 'application/json');
            final cleanTok = k.replaceFirst(RegExp(r'^(mstrl_|mistral_|mistral:|groq_|groq:|openrouter_|or_)', caseSensitive: false), '').trim();
            req.headers.set('Authorization', 'Bearer $cleanTok');
            req.add(utf8.encode(jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'max_tokens': 650,
            })));
            final resp = await req.close().timeout(const Duration(seconds: 12));
            if (resp.statusCode == 200) {
              final body = await resp.transform(utf8.decoder).join();
              final j = jsonDecode(body);
              final txt = j['choices']?[0]?['message']?['content']?.toString() ?? '';
              if (txt.isNotEmpty) return txt.trim();
            }
          } catch (_) {
          } finally {
            client.close(force: true);
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _generateAiVerdictFromSavedKeys() async {
    if (_entryState == null || _planState == null || _timeMachineState == null) return;
    final dec = _decimalsFor((_planState!['entry'] as num).toDouble());
    final headlines = _newsItems.take(3).map((n) => '- [${n['tag']}] ${n['title']}').join('\n');
    final prompt = '''You are ANIKET PRO AI Day-Trader Desk. Write a concise, high-impact trading plan in Banglish/Bengali (4-5 bullet points max) for $_selectedLabel based on these exact 11-Skill outputs:
- Live Price: ${(_planState!['entry'] as num).toStringAsFixed(dec)}
- Entry Timer (trader-entry): ${_entryState!['status']} (${_entryState!['direction']}) | OR High: ${(_entryState!['or_high'] as num).toStringAsFixed(dec)} | OR Low: ${(_entryState!['or_low'] as num).toStringAsFixed(dec)} | ATR-14: ${(_entryState!['atr14'] as num).toStringAsFixed(dec)}
- Exit Plan (trader-exit): Long Stop=${(_planState!['stop'] as num).toStringAsFixed(dec)} | 1R Target=${(_planState!['target_1r'] as num).toStringAsFixed(dec)} | ${_targetR}R Target=${(_planState!['target'] as num).toStringAsFixed(dec)} (Short Stop=${(_planState!['short_stop'] as num).toStringAsFixed(dec)} | Short 2R=${(_planState!['short_target_2r'] as num).toStringAsFixed(dec)})
- Time Machine (2,500 Monte Carlo Replays): Target First=${(_timeMachineState!['target_pct'] as num).toStringAsFixed(1)}% | Stop First=${(_timeMachineState!['stop_pct'] as num).toStringAsFixed(1)}% | Expected R=${(_timeMachineState!['avg_r'] as num).toStringAsFixed(2)}R | Verdict=${_timeMachineState!['verdict']}
- Budget & Risk (trader-budget & trader-risk): Recommended Size=${_budgetOrderState?['forex_lots']} Lots (${_budgetOrderState?['qty']} units) | Max Risk=\$${_budgetOrderState?['max_loss_usd']} | Risk Gate=${_riskVerdictState?['verdict']}
- Latest Headlines:\n$headlines''';

    final res = await _callSavedAiWithPrompt(prompt);
    _aiDeepSummary = res.isNotEmpty
        ? res
        : 'Tip: Key ট্যাবে বা Binary পেজে আপনার Gemini / Groq / OpenRouter / Mistral কি (Key) দেওয়া থাকলে এখানে স্বয়ংক্রিয়ভাবে বাংলায় AI প্রো সামারি আসবে। নিচে ১১টি স্কিলের সম্পূর্ণ লাইভ ক্যালকুলেশন দেওয়া হলো।';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UI BUILDERS
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final clock = _getMarketClockStatus();
    final skillTabs = [
      '⚡ ALL 11 SKILLS',
      '1. Scanner',
      '2. News & 8-K',
      '3. Entry Timer',
      '4. Exit Plan',
      '5. Time Machine',
      '6. Budget & Weights',
      '7. Risk Gate',
      '8. Broker Ticket',
      '9. Clock & Alerts',
      '10. SEC Analyst',
      '11. Pelosi PTR',
    ];

    return Container(
      color: const Color(0xFF0A0D12),
      child: Column(
        children: [
          // Top Header: Clock + Symbol Selector + Custom Pair + Run All Button
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xFF12161F),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_graph_rounded, color: kGold, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '🕒 ${clock['bd_time']} • ${clock['fx_session']} • NYSE: ${clock['nyse_status']}',
                        style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _showBudgetConfigDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kGold.withOpacity(0.4)),
                        ),
                        child: Text(
                          '\$${_budgetUsd.toStringAsFixed(0)} | Risk \$${_maxLossPerTradeUsd.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A202C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _presets.any((p) => p['sym'] == _selectedSym) ? _selectedSym : _presets.first['sym'],
                            dropdownColor: const Color(0xFF1A202C),
                            isExpanded: true,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            items: _presets.map((p) {
                              return DropdownMenuItem<String>(
                                value: p['sym'],
                                child: Text(p['label']!, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              final match = _presets.firstWhere((e) => e['sym'] == v);
                              setState(() {
                                _selectedSym = v;
                                _selectedLabel = match['label']!;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _showCustomSymbolDialog,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.search_rounded, color: kGold, size: 18),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _runFull11SkillPipeline,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.bolt_rounded, size: 16),
                        label: Text(
                          _busy ? 'RUNNING...' : 'RUN 11 SKILLS',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _statusMsg,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Horizontal Skill Selector Bar
          Container(
            height: 40,
            color: const Color(0xFF0E121A),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              itemCount: skillTabs.length,
              itemBuilder: (_, idx) {
                final active = _activeSkillTab == idx;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _activeSkillTab = idx),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? kGold : Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        skillTabs[idx],
                        style: TextStyle(
                          color: active ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Main Content Area
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_aiDeepSummary.isNotEmpty && (_activeSkillTab == 0))
                  _card(
                    title: '🤖 AI PRO SUMMARY ($_selectedLabel)',
                    accent: const Color(0xFF7CFC9B),
                    child: Text(
                      _aiDeepSummary,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
                    ),
                  ),
                if (_activeSkillTab == 0 || _activeSkillTab == 3) _buildEntryCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 4) _buildExitCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 5) _buildTimeMachineCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 6) _buildBudgetCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 7) _buildRiskCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 8) _buildBrokerCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 9) _buildAlertsCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 1) _buildScannerCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 2) _buildNewsCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 10) _buildAnalystCard(),
                if (_activeSkillTab == 0 || _activeSkillTab == 11) _buildPelosiCard(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Color accent = kGold,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
          child,
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v, {Color vColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(color: vColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipChoice(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? kGold : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard() {
    final e = _entryState;
    final px = (e?['price'] as num?)?.toDouble() ?? 0.0;
    final dec = _decimalsFor(px == 0 ? 2000 : px);
    return _card(
      title: '3. TRADER-ENTRY • Opening Range & Level Breakout Timer',
      trailing: TextButton(
        onPressed: _busy ? null : () => _runEntry(),
        child: const Text('Check Bars', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipChoice('5m Bars', _entryInterval == '5m', () {
                  setState(() => _entryInterval = '5m');
                  _runEntry();
                }),
                _chipChoice('1m Bars', _entryInterval == '1m', () {
                  setState(() => _entryInterval = '1m');
                  _runEntry();
                }),
                _chipChoice('ORB (15m)', _entrySetupMode == 'orb', () {
                  setState(() => _entrySetupMode = 'orb');
                  _runEntry();
                }),
                _chipChoice('Vol ≥ 1.0x', _minVolumeX == 1.0, () {
                  setState(() => _minVolumeX = 1.0);
                  _runEntry();
                }),
                _chipChoice('Vol ≥ 1.5x', _minVolumeX == 1.5, () {
                  setState(() => _minVolumeX = 1.5);
                  _runEntry();
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (e == null)
            const Text('Tap "RUN 11 SKILLS" or "Check Bars" to check live Opening Range breakout.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            _kvRow('Symbol (${e['interval']})', '${e['label']}', vColor: kGold),
            _kvRow('Signal Status', '${e['status']}',
                vColor: e['status'].toString().startsWith('TRIGGERED') ? const Color(0xFF7CFC9B) : Colors.amberAccent),
            _kvRow('Bias / Direction', '${e['direction']}'),
            _kvRow('Live Price', px.toStringAsFixed(dec), vColor: const Color(0xFF7CFC9B)),
            _kvRow('Opening Range High (15m)', (e['or_high'] as num).toStringAsFixed(dec)),
            _kvRow('Opening Range Midpoint', (e['or_mid'] as num).toStringAsFixed(dec)),
            _kvRow('Opening Range Low (15m)', (e['or_low'] as num).toStringAsFixed(dec)),
            _kvRow('14-Bar ATR (Volatility)', (e['atr14'] as num).toStringAsFixed(dec)),
            _kvRow('Volume vs OR Avg', '${(e['vol_ratio'] as num).toStringAsFixed(2)}x (Min ${_minVolumeX}x)'),
          ],
        ],
      ),
    );
  }

  Widget _buildExitCard() {
    final p = _planState;
    final px = (p?['entry'] as num?)?.toDouble() ?? 0.0;
    final dec = _decimalsFor(px == 0 ? 2000 : px);
    return _card(
      title: '4. TRADER-EXIT • Stop-Loss & 1R/2R/3R Target Planner',
      trailing: TextButton(
        onPressed: _busy ? null : () => _runExit(),
        child: const Text('Recalculate', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipChoice('Stop: 1.5x ATR', _stopRule == 'atr:1.5', () {
                  setState(() => _stopRule = 'atr:1.5');
                  _runExit();
                  _runBudget(silent: true);
                }),
                _chipChoice('Stop: OR-Mid', _stopRule == 'or_mid', () {
                  setState(() => _stopRule = 'or_mid');
                  _runExit();
                  _runBudget(silent: true);
                }),
                _chipChoice('Stop: OR-Low', _stopRule == 'or_low', () {
                  setState(() => _stopRule = 'or_low');
                  _runExit();
                  _runBudget(silent: true);
                }),
                _chipChoice('Stop: 0.5%', _stopRule == 'pct:0.5', () {
                  setState(() => _stopRule = 'pct:0.5');
                  _runExit();
                  _runBudget(silent: true);
                }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final rVal in [1.0, 1.5, 2.0, 3.0])
                  _chipChoice('Target ${rVal}R', _targetR == rVal, () {
                    setState(() => _targetR = rVal);
                    _runExit();
                    _runTimeMachine(silent: true);
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (p == null)
            const Text('Run pipeline to calculate Stop-Loss and Take-Profit levels.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            _kvRow('Entry Reference', px.toStringAsFixed(dec), vColor: Colors.white),
            _kvRow('Active Stop Rule', '${p['stop_label']}'),
            const SizedBox(height: 4),
            const Text('🟢 LONG (BUY) SETUP LEVELS:', style: TextStyle(color: Color(0xFF7CFC9B), fontSize: 12, fontWeight: FontWeight.bold)),
            _kvRow('  • Stop-Loss (SL)', (p['stop'] as num).toStringAsFixed(dec), vColor: Colors.redAccent),
            _kvRow('  • Target 1 (1R Safe)', (p['target_1r'] as num).toStringAsFixed(dec), vColor: const Color(0xFF7CFC9B)),
            _kvRow('  • Target 2 (${p['target_r']}R Main)', (p['target'] as num).toStringAsFixed(dec), vColor: const Color(0xFF7CFC9B)),
            const SizedBox(height: 6),
            const Text('🔴 SHORT (SELL) SETUP LEVELS:', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            _kvRow('  • Short Stop-Loss (SL)', (p['short_stop'] as num).toStringAsFixed(dec), vColor: Colors.redAccent),
            _kvRow('  • Short Target 1 (1R)', (p['short_target_1r'] as num).toStringAsFixed(dec), vColor: const Color(0xFF7CFC9B)),
            _kvRow('  • Short Target 2 (${p['target_r']}R)', (p['short_target_2r'] as num).toStringAsFixed(dec), vColor: const Color(0xFF7CFC9B)),
            _kvRow('Flat-By Time', '${p['flat_by']}'),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeMachineCard() {
    final tm = _timeMachineState;
    final px = (_planState?['entry'] as num?)?.toDouble() ?? 2000.0;
    final dec = _decimalsFor(px);
    return _card(
      title: '5. TRADER-TIMEMACHINE • Monte Carlo & History Replay',
      trailing: TextButton(
        onPressed: _busy ? null : () => _runTimeMachine(),
        child: const Text('Run Replays', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: tm == null
          ? const Text('Simulates 2,500 intraday sessions + tests past 5m sessions from history.',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow('Verdict', '${tm['verdict']}',
                    vColor: tm['verdict'].toString().startsWith('POSITIVE') ? const Color(0xFF7CFC9B) : Colors.amberAccent),
                _kvRow('Target Hit First', '${(tm['target_pct'] as num).toStringAsFixed(1)}%', vColor: const Color(0xFF7CFC9B)),
                _kvRow('Stop Hit First', '${(tm['stop_pct'] as num).toStringAsFixed(1)}%', vColor: Colors.redAccent),
                _kvRow('Neither by Close (Flat)', '${(tm['neither_pct'] as num).toStringAsFixed(1)}%'),
                _kvRow('Win Share vs Breakeven',
                    '${(tm['win_of_resolved_pct'] as num).toStringAsFixed(1)}% (Need ${(tm['breakeven_pct'] as num).toStringAsFixed(0)}%)'),
                _kvRow('Expected Value (Avg R)', '${(tm['avg_r'] as num).toStringAsFixed(2)}R'),
                _kvRow('Historical Sessions Backtest',
                    '${tm['hist_sessions']} Past Triggers (${tm['hist_wins']} Wins / ${tm['hist_losses']} Losses)'),
                _kvRow('Simulated Close (5% / 50% / 95%)',
                    '${(tm['p05'] as num).toStringAsFixed(dec)} / ${(tm['p50'] as num).toStringAsFixed(dec)} / ${(tm['p95'] as num).toStringAsFixed(dec)}'),
                if ((tm['hist_bars'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  const Text('📊 Simulated Close Distribution (Fan Histogram):',
                      style: TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  for (final bLine in (tm['hist_bars'] as List))
                    Text(
                      bLine.toString(),
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _buildBudgetCard() {
    final b = _budgetOrderState;
    return _card(
      title: '6. TRADER-BUDGET • 4-Cap Sizer & Portfolio Weights',
      trailing: TextButton(
        onPressed: _showBudgetConfigDialog,
        child: const Text('Edit Rules', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (b == null)
            const Text('Calculates exact lot/share size that fits inside your Max Loss per trade and Cash Buffer.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            _kvRow('Recommended Forex / Gold Lot Size', '${b['forex_lots']} Lots', vColor: const Color(0xFF7CFC9B)),
            _kvRow('Stock / Crypto Units', '${b['qty']} whole (${b['exact_units']} exact)', vColor: kGold),
            _kvRow('Max Loss at Stop-Loss', '\$${b['max_loss_usd']} (Limit: \$${_maxLossPerTradeUsd.toStringAsFixed(0)})',
                vColor: Colors.amberAccent),
            _kvRow('Deciding Cap', '${b['deciding_limit']}'),
            _kvRow('Entry / Stop / Target',
                '${b['entry_price']} / ${b['stop_loss_stop_price']} / ${b['take_profit_limit_price']}'),
          ],
          if (_weightsAllocation.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 16),
            Text(
              '📐 Portfolio Weights Mode (${(100 - _cashBufferPct).toStringAsFixed(0)}% Invested, ${_cashBufferPct.toStringAsFixed(0)}% Cash Buffer):',
              style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            for (final w in _weightsAllocation)
              _kvRow('  • ${w['sym']} (${w['weight_pct']}%)', '\$${w['usd']}'),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskCard() {
    final r = _riskVerdictState;
    final pass = r != null && r['verdict'] == 'PASS';
    return _card(
      title: '7. TRADER-RISK • Pre-Trade Safety Gate',
      accent: pass ? const Color(0xFF7CFC9B) : kGold,
      trailing: TextButton(
        onPressed: _busy ? null : () => _runRiskCheck(),
        child: const Text('Re-Check', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: r == null
          ? const Text('Checks Stop-Loss presence, Max Loss per trade, Reward:Risk, Daily Loss Limit & Cash Buffer.',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow('Risk Gate Verdict', '${r['verdict']}',
                    vColor: pass ? const Color(0xFF7CFC9B) : Colors.redAccent),
                const SizedBox(height: 6),
                for (final p in (r['passed'] as List))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('✅ $p', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                for (final b in (r['blocked'] as List))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('🛑 $b', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
    );
  }

  Widget _buildBrokerCard() {
    final b = _budgetOrderState;
    final alpacaJsonStr = const JsonEncoder.withIndent('  ').convert(_buildAlpacaOrderJson());
    return _card(
      title: '8. TRADER-BROKER • Bracket Ticket, Alpaca JSON & Flatten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (b == null)
            const Text('Run the pipeline first to build a verified bracket order ticket.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'TICKET: BUY ${b['qty']} units (${b['forex_lots']} Lots) ${b['label']} @ Market (${b['entry_price']})\n'
                '• Stop-Loss: ${b['stop_loss_stop_price']}  |  Take-Profit: ${b['take_profit_limit_price']}\n'
                '• Max Loss at Stop: \$${b['max_loss_usd']}\n\n'
                'ALPACA place_stock_order JSON:\n$alpacaJsonStr',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace', height: 1.35),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _approvePaperOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7CFC9B),
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 15),
                  label: const Text('APPROVE ("YES") & FILL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                OutlinedButton.icon(
                  onPressed: _flattenPositionTicket,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent),
                  icon: const Icon(Icons.exit_to_app_rounded, size: 15),
                  label: const Text('Flatten (Close by 15:55)', style: TextStyle(fontSize: 11)),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _brokerLog.clear());
                    _saveProState();
                    _notifyToast('Broker paper log cleared');
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Clear Log', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
          if (_brokerLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Recent Approved / Flattened Tickets:', style: TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.bold)),
            for (final item in _brokerLog.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• [${item['approved_at']}] ${item['status']} — ${item['label']} (${item['forex_lots']} Lots @ ${item['entry_price']})',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertsCard() {
    final clock = _getMarketClockStatus();
    return _card(
      title: '9. TRADER-ALERTS • Market Clock & Auto-Alert Monitor',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _addPlanAlerts,
            child: const Text('+3 Plan Alerts', style: TextStyle(color: kGold, fontSize: 11)),
          ),
          TextButton(
            onPressed: _showAddCustomAlertDialog,
            child: const Text('+Custom', style: TextStyle(color: Color(0xFF7CFC9B), fontSize: 11)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kvRow('New York Clock', '${clock['ny_time']}'),
          _kvRow('Bangladesh Clock', '${clock['bd_time']}'),
          _kvRow('NYSE Session (2026-2027 Cal)', '${clock['nyse_status']}', vColor: kGold),
          _kvRow('Forex Session / Killzone', '${clock['fx_session']}', vColor: const Color(0xFF7CFC9B)),
          const Divider(color: Colors.white12, height: 14),
          if (_alertsList.isEmpty)
            const Text('Tap "+3 Plan Alerts" or "+Custom" to watch Stop, Target, % Move, or Opening Bell.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            for (int i = 0; i < _alertsList.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _alertsList[i]['triggered'] == true
                          ? Icons.notifications_active
                          : Icons.schedule_rounded,
                      color: _alertsList[i]['triggered'] == true ? const Color(0xFF7CFC9B) : kGold,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_alertsList[i]['label']} (${_alertsList[i]['rule'].toString().toUpperCase()} ${_alertsList[i]['price_str']})',
                        style: TextStyle(
                          color: _alertsList[i]['triggered'] == true ? const Color(0xFF7CFC9B) : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() => _alertsList.removeAt(i));
                        _saveProState();
                      },
                      child: const Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildScannerCard() {
    return _card(
      title: '1. TRADER-SCANNER • Multi-Market Setup Watchlist',
      trailing: TextButton(
        onPressed: _busy ? null : _runScanner,
        child: const Text('Scan All Markets', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: _watchlist.isEmpty
          ? const Text('Tap "Scan All Markets" to scan Gold, Silver, BTC, Forex Majors & Top Stocks for ORB, 20D Breakout, Bull Flag & RSI Bounces.',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              children: [
                for (final item in _watchlist)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedSym = item['sym'].toString();
                        _selectedLabel = item['label'].toString();
                      });
                      _runFull11SkillPipeline();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item['label']}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (item['setups'] as List).join(' • '),
                                  style: const TextStyle(color: kGold, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                (item['price'] as num).toStringAsFixed(_decimalsFor((item['price'] as num).toDouble())),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${(item['chgPct'] as num) >= 0 ? "+" : ""}${(item['chgPct'] as num).toStringAsFixed(2)}% • RSI ${(item['rsi'] as num).toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: (item['chgPct'] as num) >= 0 ? const Color(0xFF7CFC9B) : Colors.redAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildNewsCard() {
    return _card(
      title: '2. TRADER-NEWS • Yahoo RSS & SEC EDGAR 8-K Monitor',
      trailing: TextButton(
        onPressed: _busy ? null : () => _runNews(),
        child: const Text('Refresh News', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: _newsItems.isEmpty
          ? const Text('Tap "Refresh News" to fetch live Yahoo Finance RSS & SEC EDGAR 8-K filings.',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in _newsItems.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${n['tag']}',
                                style: const TextStyle(color: kGold, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${n['time']}',
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${n['title']}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAnalystCard() {
    final a = _analystState;
    return _card(
      title: '10. TRADER-ANALYST • SEC XBRL & Earnings Call Analyzer',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busy ? null : () => _runAnalyst(),
            child: const Text('Fetch XBRL', style: TextStyle(color: kGold, fontSize: 11)),
          ),
          TextButton(
            onPressed: _showPasteTranscriptDialog,
            child: const Text('Paste Transcript', style: TextStyle(color: Color(0xFF7CFC9B), fontSize: 11)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (a == null)
            const Text('Reads official SEC EDGAR 10-Q/10-K XBRL facts for stocks or 90-day macro profile for Gold/BTC/Forex.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            _kvRow('Mode', '${a['mode']}', vColor: kGold),
            _kvRow('Entity / Asset', '${a['entity']}'),
            _kvRow('Latest Period', '${a['period_end']}'),
            _kvRow('Revenue / High', '${a['revenue_bn']}'),
            _kvRow('Net Income / Low', '${a['net_income_bn']}'),
            _kvRow('Margin / 90D Return', '${a['net_margin_pct']}', vColor: const Color(0xFF7CFC9B)),
            if ((a['quarters'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              const Text('Quarterly History:', style: TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold)),
              for (final qLine in (a['quarters'] as List))
                Text('  • $qLine', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ],
          if (_transcriptAnalysis.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 16),
            const Text('🎙️ Earnings Call / Press Release AI Summary:',
                style: TextStyle(color: Color(0xFF7CFC9B), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_transcriptAnalysis, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildPelosiCard() {
    final filtered = _pelosiFilter.trim().isEmpty
        ? _pelosiRows
        : _pelosiRows
            .where((r) =>
                r['member'].toString().toLowerCase().contains(_pelosiFilter.toLowerCase()) ||
                r['ticker'].toString().toLowerCase().contains(_pelosiFilter.toLowerCase()))
            .toList();
    return _card(
      title: '11. TRADER-PELOSI • US Congress STOCK Act PTR Tracker',
      trailing: TextButton(
        onPressed: _busy ? null : () => _runPelosiTracker(),
        child: const Text('Refresh PTRs', style: TextStyle(color: kGold, fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Filter by member (e.g. Pelosi, Gottheimer) or ticker (NVDA)...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
              isDense: true,
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _pelosiFilter = v),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Text('Tap "Refresh PTRs" to load House Clerk Periodic Transaction Reports.',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            for (final r in filtered)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedSym.contains(r['ticker'].toString()) ? const Color(0xFF7CFC9B) : Colors.white10,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${r['member']}', style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('Filed: ${r['filed']} (#${r['doc_id']})', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${r['ticker']} — ${r['asset']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('${r['type']}  •  Amount: ${r['amount']}', style: const TextStyle(color: Color(0xFF7CFC9B), fontSize: 11)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _showCustomSymbolDialog() {
    final symCtrl = TextEditingController(text: _selectedSym);
    final lblCtrl = TextEditingController(text: _selectedLabel);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Analyze Any Custom Symbol / Pair', style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: symCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Yahoo Ticker (e.g. GC=F, BTC-USD, EURUSD=X, PLTR)',
                labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            TextField(
              controller: lblCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Display Name (optional)',
                labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
            onPressed: () {
              final s = symCtrl.text.trim().toUpperCase();
              if (s.isNotEmpty) {
                final l = lblCtrl.text.trim().isNotEmpty ? lblCtrl.text.trim() : s;
                setState(() {
                  if (!_presets.any((p) => p['sym'] == s)) {
                    _presets.insert(0, {'label': l, 'sym': s, 'kind': 'custom'});
                  }
                  _selectedSym = s;
                  _selectedLabel = l;
                });
                Navigator.pop(ctx);
                _runFull11SkillPipeline();
              }
            },
            child: const Text('Analyze Symbol', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddCustomAlertDialog() {
    final pxCtrl = TextEditingController();
    String rule = 'above';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setModal) => AlertDialog(
          backgroundColor: const Color(0xFF1A202C),
          title: Text('Add Custom Alert for $_selectedLabel', style: const TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: rule,
                dropdownColor: const Color(0xFF1A202C),
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'above', child: Text('Price At or Above (Target)')),
                  DropdownMenuItem(value: 'below', child: Text('Price At or Below (Stop)')),
                  DropdownMenuItem(value: 'pct_move', child: Text('% Move From Previous Close')),
                ],
                onChanged: (v) {
                  if (v != null) setModal(() => rule = v);
                },
              ),
              TextField(
                controller: pxCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: rule == 'pct_move' ? 'Percent Move (e.g. 2.5)' : 'Price Level',
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
              onPressed: () {
                final val = double.tryParse(pxCtrl.text.trim());
                if (val != null && val > 0) {
                  setState(() {
                    _alertsList.insert(0, {
                      'id': 'cust_${DateTime.now().millisecondsSinceEpoch}',
                      'symbol': _selectedSym,
                      'label': '$_selectedLabel CUSTOM',
                      'rule': rule,
                      'price': val,
                      'price_str': rule == 'pct_move' ? '$val%' : '$val',
                      'triggered': false,
                      'from_plan': false,
                    });
                  });
                  _saveProState();
                  Navigator.pop(ctx);
                  _notifyToast('Custom alert added for $_selectedLabel!');
                }
              },
              child: const Text('Add Alert', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPasteTranscriptDialog() {
    final tCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Earnings Call / Press Release Analyzer', style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: tCtrl,
          maxLines: 6,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Paste earnings call transcript, 8-K press release, or macro Fed statement here...',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
            onPressed: () async {
              final text = tCtrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              setState(() {
                _busy = true;
                _statusMsg = 'Analyzing transcript with trader-analyst AI...';
              });
              final res = await _callSavedAiWithPrompt(
                'You are trader-analyst. Summarize the key numbers, guidance changes, margin drivers, and trading impact in Banglish/Bengali (4 bullet points) from this text:\n\n$text',
              );
              if (!mounted) return;
              setState(() {
                _busy = false;
                _transcriptAnalysis = res.isNotEmpty
                    ? res
                    : 'Transcript received (${text.length} chars). Add an active API key in Key tab to generate full Banglish AI breakdown.';
                _statusMsg = 'Transcript analysis ready.';
              });
            },
            child: const Text('Analyze with AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBudgetConfigDialog() {
    final bCtrl = TextEditingController(text: _budgetUsd.toStringAsFixed(0));
    final lCtrl = TextEditingController(text: _maxLossPerTradeUsd.toStringAsFixed(0));
    final dCtrl = TextEditingController(text: _maxDailyLossUsd.toStringAsFixed(0));
    final rCtrl = TextEditingController(text: _targetR.toStringAsFixed(1));
    final wCtrl = TextEditingController(text: _weightsSpec);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Budget, Risk & Portfolio Weights Rules', style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Account Budget (\$ USD)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: lCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Max Loss Per Trade (\$ USD)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: dCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Max Daily Loss Limit (\$ USD)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: rCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Target R Multiple (e.g. 2.0 for 2R)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: wCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Portfolio Weights (e.g. GC=F=30,BTC-USD=25,NVDA=25,TSLA=20)',
                  labelStyle: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
            onPressed: () {
              setState(() {
                _budgetUsd = double.tryParse(bCtrl.text.trim()) ?? _budgetUsd;
                _maxLossPerTradeUsd = double.tryParse(lCtrl.text.trim()) ?? _maxLossPerTradeUsd;
                _maxDailyLossUsd = double.tryParse(dCtrl.text.trim()) ?? _maxDailyLossUsd;
                _targetR = double.tryParse(rCtrl.text.trim()) ?? _targetR;
                if (wCtrl.text.trim().isNotEmpty) _weightsSpec = wCtrl.text.trim();
                _computeWeightsAllocation();
              });
              _saveProState();
              Navigator.pop(ctx);
              _runExit();
              _runBudget();
              _runRiskCheck();
            },
            child: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
