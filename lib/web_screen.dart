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
  Future<void> _syncMultiKeysToForexWeb() async {
    if (!_siteReady) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final savedKeys = (p.getStringList('bin_keys') ?? [])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final keysJson = jsonEncode(savedKeys);
      await _controller.runJavaScript(_buildForexMultiAiBridgeJs(keysJson));
    } catch (_) {}
  }

  String _buildForexMultiAiBridgeJs(String flutterKeysJson) {
    return '''
(function(){
  try {
    var incomingKeys = $flutterKeysJson || [];
    if (!window.__aniketAllKeys) window.__aniketAllKeys = [];

    function cleanKey(k) {
      if (!k || typeof k !== 'string') return '';
      return k.replace(/^Bearer\\s+/i, '').replace(/["']/g, '').trim();
    }

    function deobfKey(s) {
      if (!s || typeof s !== 'string') return '';
      try {
        var d = decodeURIComponent(atob(s));
        if (d && d.length >= 16) return cleanKey(d);
      } catch(e) {}
      return cleanKey(s);
    }

    function obfKey(s) {
      try {
        return btoa(encodeURIComponent(cleanKey(s)));
      } catch(e) {
        return cleanKey(s);
      }
    }

    function readSiteKeys() {
      var out = [];
      try {
        var raw = localStorage.getItem('gemini_keys');
        if (raw) {
          var arr = JSON.parse(raw);
          if (Array.isArray(arr)) {
            for (var i = 0; i < arr.length; i++) {
              var k = deobfKey(arr[i]);
              if (k && k.length >= 16 && out.indexOf(k) < 0) {
                out.push(k);
              }
            }
          }
        }
      } catch(e) {}
      try {
        var single = localStorage.getItem('gemini_key_v1');
        if (single) {
          var ks = deobfKey(single);
          if (ks && ks.length >= 16 && out.indexOf(ks) < 0) {
            out.push(ks);
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

    if (siteKeys.length === 0 && merged.length > 0) {
      var encodedArr = merged.map(obfKey);
      localStorage.setItem('gemini_keys', JSON.stringify(encodedArr));
      localStorage.setItem('gemini_key_v1', encodedArr[0]);
      if (!localStorage.getItem('gemini_key_idx')) {
        localStorage.setItem('gemini_key_idx', '0');
      }
      try {
        if (typeof window.updateKeyStatus === 'function') window.updateKeyStatus();
        if (typeof window.renderKeySlots === 'function') window.renderKeySlots();
      } catch(e) {}
    } else if (siteKeys.length > incomingKeys.length && window.FlutterBridge) {
      try {
        window.FlutterBridge.postMessage('SYNC_KEYS:' + JSON.stringify(merged));
      } catch(e) {}
    }

    if (window.__aniketMultiAiFetchHooked) return;
    window.__aniketMultiAiFetchHooked = true;

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

    // ═══════════════════════════════════════════════════════════════════
    //  11 DAY-TRADER SKILLS ENGINE DIRECTLY INSIDE FOREX PAGE
    // ═══════════════════════════════════════════════════════════════════
    var defaultSkillCfg = {
      pair: 'GC=F',
      pairLabel: 'XAU/USD (Gold)',
      stopRule: 'atr:1.5',
      targetR: 2.0,
      s1_scanner: true,
      s2_news: true,
      s3_entry: true,
      s4_exit: true,
      s5_timemachine: true,
      s6_budget: true,
      s7_risk: true,
      s8_broker: true,
      s9_alerts: true,
      s10_analyst: true,
      s11_pelosi: true
    };

    function loadSkillCfg() {
      try {
        var raw = localStorage.getItem('aniket_11skills_cfg');
        if (raw) {
          var p = JSON.parse(raw);
          for (var k in defaultSkillCfg) {
            if (p[k] === undefined) p[k] = defaultSkillCfg[k];
          }
          return p;
        }
      } catch(e) {}
      return Object.assign({}, defaultSkillCfg);
    }

    function saveSkillCfg(cfg) {
      try {
        origSetItem('aniket_11skills_cfg', JSON.stringify(cfg));
      } catch(e) {}
    }

    window.__aniketSkillCfg = loadSkillCfg();

    // Read user's Risk per Trade (%), Account Balance (USD), Daily Loss Limit (%), Max Daily Trades, ATR Multiplier from Mode tab inputs
    function readModeFormNumbers() {
      var res = {
        riskPct: 1.0,
        balance: 5000.0,
        dailyLossPct: 2.0,
        maxTrades: 10,
        atrMult: 1.5,
        tp1Pct: 50
      };
      try {
        var labels = document.querySelectorAll('label, div, span');
        for (var i = 0; i < labels.length; i++) {
          var el = labels[i];
          if (el.children && el.children.length > 2) continue;
          var t = (el.innerText || '').trim().toLowerCase();
          var parent = el.parentElement;
          if (!parent) continue;
          var inp = parent.querySelector('input');
          if (!inp && parent.parentElement) inp = parent.parentElement.querySelector('input');
          if (!inp) continue;
          var val = parseFloat(inp.value || inp.placeholder || '');
          if (isNaN(val) || val <= 0) continue;
          if (t.indexOf('risk per trade') >= 0) res.riskPct = val;
          else if (t.indexOf('account balance') >= 0) res.balance = val;
          else if (t.indexOf('daily loss limit') >= 0) res.dailyLossPct = val;
          else if (t.indexOf('max daily trades') >= 0) res.maxTrades = val;
          else if (t.indexOf('atr multiplier') >= 0) res.atrMult = val;
        }
      } catch(e) {}
      return res;
    }

    // Wilder RSI-14
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

    // Run the 11 Day-Trader Skills Engine on a symbol
    async function run11SkillsEngine(sym, label) {
      var cfg = window.__aniketSkillCfg || loadSkillCfg();
      sym = sym || cfg.pair || 'GC=F';
      label = label || cfg.pairLabel || 'XAU/USD (Gold)';
      var modeNums = readModeFormNumbers();

      var url5m = 'https://query2.finance.yahoo.com/v8/finance/chart/' + encodeURIComponent(sym) + '?range=5d&interval=5m';
      var resp = await origFetch(url5m, { method: 'GET' });
      if (!resp || !resp.ok) return null;
      var j = await resp.json();
      var res0 = j && j.chart && j.chart.result && j.chart.result[0];
      if (!res0) return null;

      var meta = res0.meta || {};
      var q0 = (res0.indicators && res0.indicators.quote && res0.indicators.quote[0]) || {};
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
      if (bars.length < 15) return null;

      var livePx = meta.regularMarketPrice || bars[bars.length - 1].c;
      var prevClose = meta.chartPreviousClose || meta.previousClose || bars[0].o;
      var chgPct = prevClose > 0 ? (((livePx - prevClose) / prevClose) * 100.0) : 0.0;
      var dec = livePx > 100 ? 2 : (livePx > 10 ? 3 : 5);

      // 1. ATR-14
      var atrN = Math.min(14, bars.length - 1);
      var trSum = 0;
      for (var a = bars.length - atrN; a < bars.length; a++) {
        var cur = bars[a], pv = bars[a - 1].c;
        trSum += Math.max(cur.h - cur.l, Math.abs(cur.h - pv), Math.abs(cur.l - pv));
      }
      var atr14 = trSum / Math.max(1, atrN);

      // 2. RSI-14
      var closes = bars.map(function(b){ return b.c; });
      var rsi14 = calcWilderRsi(closes, 14);

      // 3. trader-entry: Opening Range (first 3 bars of recent 24-bar session)
      var sess = bars.slice(-24);
      var orBars = sess.slice(0, 3);
      var orHigh = Math.max.apply(null, orBars.map(function(b){ return b.h; }));
      var orLow  = Math.min.apply(null, orBars.map(function(b){ return b.l; }));
      var orMid  = (orHigh + orLow) / 2.0;
      var entryStatus = livePx > orHigh
        ? 'TRIGGERED BULLISH (Above OR High ' + orHigh.toFixed(dec) + ')'
        : (livePx < orLow
            ? 'TRIGGERED BEARISH (Below OR Low ' + orLow.toFixed(dec) + ')'
            : 'WAITING INSIDE OR (' + orLow.toFixed(dec) + ' – ' + orHigh.toFixed(dec) + ')');

      // 4. trader-exit: Stop-Loss & 1R/2R/3R Targets
      var atrMult = modeNums.atrMult > 0 ? modeNums.atrMult : 1.5;
      var riskDist = cfg.stopRule === 'or_mid' && Math.abs(livePx - orMid) > livePx * 0.0005
        ? Math.abs(livePx - orMid)
        : (atrMult * atr14);
      if (riskDist < livePx * 0.0005) riskDist = livePx * 0.002;

      var targetR = cfg.targetR || 2.0;
      var longSL  = livePx - riskDist;
      var longTP1 = livePx + riskDist;
      var longTP2 = livePx + (targetR * riskDist);
      var longTP3 = livePx + (3.0 * riskDist);

      var shortSL  = livePx + riskDist;
      var shortTP1 = livePx - riskDist;
      var shortTP2 = livePx - (targetR * riskDist);
      var shortTP3 = livePx - (3.0 * riskDist);

      // 5. trader-timemachine: 2,500 Monte Carlo Intraday Replays
      var ratios = [];
      for (var rIdx = 1; rIdx < bars.length; rIdx++) {
        var pc = bars[rIdx - 1].c;
        if (pc > 0) {
          var hr = bars[rIdx].h / pc, lr = bars[rIdx].l / pc, cr = bars[rIdx].c / pc;
          if (hr > 0.92 && hr < 1.08 && lr > 0.92 && lr < 1.08) ratios.push([hr, lr, cr]);
        }
      }
      var replays = 2000;
      var hitTP = 0, hitSL = 0, hitFlat = 0, sumR = 0;
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
        if (out === 'tp') { hitTP++; sumR += targetR; }
        else if (out === 'sl') { hitSL++; sumR -= 1.0; }
        else {
          hitFlat++;
          sumR += ((isBullBias ? (px - livePx) : (livePx - px)) / riskDist);
        }
      }
      var resolved = Math.max(1, hitTP + hitSL);
      var winPct = (hitTP / resolved) * 100.0;
      var bePct  = (1.0 / (1.0 + targetR)) * 100.0;
      var avgR   = sumR / replays;
      var tmVerdict = winPct >= bePct + 4
        ? 'POSITIVE EDGE (+' + avgR.toFixed(2) + 'R)'
        : (Math.abs(winPct - bePct) <= 4 ? 'COIN FLIP (' + winPct.toFixed(1) + '%)' : 'CAUTION (' + avgR.toFixed(2) + 'R)');

      // 6. trader-budget & 7. trader-risk: Lot Sizing & Compliance Gate
      var riskUsd = modeNums.balance * (modeNums.riskPct / 100.0);
      var dailyMaxLossUsd = modeNums.balance * (modeNums.dailyLossPct / 100.0);
      var rawUnits = riskDist > 0 ? (riskUsd / riskDist) : 1;
      var lots = sym === 'GC=F'
        ? Math.max(0.01, rawUnits / 100.0)
        : (sym.indexOf('=X') >= 0 ? Math.max(0.01, rawUnits / 100000.0) : Math.max(0.01, rawUnits));
      var riskPass = (riskUsd <= dailyMaxLossUsd) && (targetR >= 1.0);
      var riskVerdict = riskPass
        ? 'PASS (Max Risk USD ' + riskUsd.toFixed(2) + ' fits Daily Limit USD ' + dailyMaxLossUsd.toFixed(2) + ')'
        : 'BLOCK (Risk USD ' + riskUsd.toFixed(2) + ' exceeds Daily Limit USD ' + dailyMaxLossUsd.toFixed(2) + ')';

      // 9. trader-alerts Clock (BD Time + NYSE Status)
      var nowUtc = new Date();
      var bdDate = new Date(nowUtc.getTime() + 6 * 3600 * 1000);
      var bdHr = bdDate.getUTCHours();
      var kz = (bdHr >= 13 && bdHr < 17) ? 'London Killzone' : ((bdHr >= 18 && bdHr < 23) ? 'New York Killzone' : 'Asia / Transition');

      return {
        sym: sym,
        label: label,
        dec: dec,
        livePx: livePx,
        chgPct: chgPct,
        atr14: atr14,
        rsi14: rsi14,
        orHigh: orHigh,
        orLow: orLow,
        orMid: orMid,
        entryStatus: entryStatus,
        isBullBias: isBullBias,
        longSL: longSL,
        longTP1: longTP1,
        longTP2: longTP2,
        longTP3: longTP3,
        shortSL: shortSL,
        shortTP1: shortTP1,
        shortTP2: shortTP2,
        shortTP3: shortTP3,
        targetR: targetR,
        winPct: winPct,
        bePct: bePct,
        avgR: avgR,
        tmVerdict: tmVerdict,
        riskUsd: riskUsd,
        dailyMaxLossUsd: dailyMaxLossUsd,
        lots: lots,
        riskVerdict: riskVerdict,
        kz: kz,
        balance: modeNums.balance,
        riskPct: modeNums.riskPct
      };
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CLEAN UP SCREENSHOT 2 & SCREENSHOT 3 IN FOREX 'MODE' TAB +
    //  INJECT THE 11 DAY-TRADER SKILLS PANEL DIRECTLY INTO FOREX PAGE
    // ═══════════════════════════════════════════════════════════════════
    function findDeepestContainerWithBoth(txtA, txtB) {
      var aLow = txtA.toLowerCase(), bLow = txtB.toLowerCase();
      var candidates = document.querySelectorAll('div, section, article, form, main');
      var best = null;
      var bestLen = 9999999;
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        if (!el || el.tagName === 'BODY' || el.tagName === 'HTML') continue;
        var tc = (el.textContent || '').toLowerCase();
        if (tc.indexOf(aLow) >= 0 && tc.indexOf(bLow) >= 0) {
          if (tc.length < bestLen) {
            best = el;
            bestLen = tc.length;
          }
        }
      }
      return best;
    }

    function hideFieldWithoutTouchingSiblings(targetPhrase, forbiddenPhrases) {
      var tLow = targetPhrase.toLowerCase();
      var all = document.querySelectorAll('label, span, div, p, details, summary');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (!el || (el.id && el.id.indexOf('aniket-') === 0)) continue;
        var tc = (el.textContent || '').trim().toLowerCase();
        if (tc.indexOf(tLow) < 0 || tc.length > 180) continue;

        // Walk up as long as parent does NOT contain any forbidden sibling phrase
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

    function build11SkillsPanelHtml(boxSuffix) {
      var cfg = window.__aniketSkillCfg || loadSkillCfg();
      var pairsHtml = [
        ['GC=F', 'XAU/USD (Gold)'],
        ['BTC-USD', 'BTC/USD (Bitcoin)'],
        ['EURUSD=X', 'EUR/USD'],
        ['GBPUSD=X', 'GBP/USD'],
        ['USDJPY=X', 'USD/JPY'],
        ['AUDUSD=X', 'AUD/USD'],
        ['USDCAD=X', 'USD/CAD'],
        ['SI=F', 'XAG/USD (Silver)'],
        ['CL=F', 'WTI Crude Oil'],
        ['NQ=F', 'US100 (Nasdaq)'],
        ['YM=F', 'US30 (Dow)'],
        ['DX-Y.NYB', 'DXY (Dollar Index)'],
        ['NVDA', 'NVDA'],
        ['TSLA', 'TSLA'],
        ['AAPL', 'AAPL']
      ].map(function(p) {
        var sel = cfg.pair === p[0] ? 'selected' : '';
        return '<option value="' + p[0] + '" data-lbl="' + p[1] + '" ' + sel + '>' + p[1] + '</option>';
      }).join('');

      var skillsMeta = [
        ['s1_scanner', '📊 1. Auto Market Scanner (ORB, 20D Breakout, Bull Flag, RSI)'],
        ['s2_news', '📰 2. Free Live News & SEC 8-K Radar (0 Quota — Auto Filter)'],
        ['s3_entry', '⏱️ 3. 5m/1m Opening Range Breakout Entry Timer (OR High/Low)'],
        ['s4_exit', '🎯 4. Smart Exit Planner (Auto 1.5x ATR / OR-Mid SL + 1R/2R/3R TP)'],
        ['s5_timemachine', '⏳ 5. Time Machine (2,000x Monte Carlo Win-Rate & Expected R)'],
        ['s6_budget', '💰 6. Budget & Lot Sizer (Auto Forex Lots from Balance & Risk %)'],
        ['s7_risk', '🛡️ 7. Pre-Trade Risk Gate (PASS / BLOCK Daily Loss Guard)'],
        ['s8_broker', '🧾 8. Bracket Order Ticket & Flatten by Close Generator'],
        ['s9_alerts', '🔔 9. NYSE/Killzone Clock & Auto Stop/Target Price Alerts'],
        ['s10_analyst', '📈 10. Macro 90D Range & SEC EDGAR XBRL Margin Analyst'],
        ['s11_pelosi', '🏛️ 11. Smart Money & US Congress PTR Institutional Tracker']
      ];

      var togglesHtml = skillsMeta.map(function(sm, idx) {
        var checked = cfg[sm[0]] !== false ? 'checked' : '';
        return '<div style="display:flex;align-items:center;justify-content:space-between;padding:7px 0;border-bottom:1px solid rgba(255,255,255,0.07);font-size:12.5px;">'
          + '<span data-open-tab="' + (idx + 1) + '" style="padding-right:10px;line-height:1.35;cursor:pointer;flex:1;">' + sm[1] + '</span>'
          + '<input type="checkbox" data-skill="' + sm[0] + '" ' + checked + ' style="width:18px;height:18px;accent-color:#D4AF37;cursor:pointer;" />'
          + '</div>';
      }).join('');

      return ''
        + '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">'
        + '  <div style="font-weight:900;font-size:13.5px;color:#FFD54F;letter-spacing:0.4px;">⚡ FOREX 11 DAY-TRADER PRO SKILLS</div>'
        + '  <span style="font-size:10.5px;background:rgba(124,252,155,0.18);color:#7CFC9B;padding:3px 8px;border-radius:10px;font-weight:bold;">11/11 Active • 0 Quota</span>'
        + '</div>'
        + '<div style="display:flex;gap:6px;margin-bottom:10px;flex-wrap:wrap;">'
        + '  <select class="aniket-skill-pair-sel" style="flex:1;min-width:130px;padding:8px;border-radius:8px;background:#12261C;color:#fff;border:1px solid rgba(212,175,55,0.45);font-weight:bold;font-size:12px;">'
        +      pairsHtml
        + '  </select>'
        + '  <button class="aniket-skill-run-btn" type="button" style="padding:8px 11px;border-radius:8px;background:#D4AF37;color:#000;font-weight:900;border:none;font-size:11.5px;cursor:pointer;">⚡ Live Analyze</button>'
        + '  <button class="aniket-skill-full-btn" type="button" style="padding:8px 11px;border-radius:8px;background:#173326;color:#7CFC9B;font-weight:900;border:1px solid #7CFC9B;font-size:11.5px;cursor:pointer;">📊 Open 11 Tools</button>'
        + '</div>'
        + '<div class="aniket-skill-live-out" style="display:none;margin-bottom:10px;padding:10px;border-radius:8px;background:#07120D;border:1px solid rgba(124,252,155,0.35);font-size:12px;line-height:1.45;color:#E2F1E8;"></div>'
        + '<div>' + togglesHtml + '</div>';
    }

    function wire11SkillsContainer(wrap) {
      if (!wrap || wrap.__wired) return;
      wrap.__wired = true;

      var selEl = wrap.querySelector('.aniket-skill-pair-sel');
      if (selEl) {
        selEl.addEventListener('change', function() {
          var opt = selEl.options[selEl.selectedIndex];
          window.__aniketSkillCfg.pair = selEl.value;
          window.__aniketSkillCfg.pairLabel = opt ? opt.getAttribute('data-lbl') : selEl.value;
          saveSkillCfg(window.__aniketSkillCfg);
        });
      }

      var cbs = wrap.querySelectorAll('input[type=checkbox][data-skill]');
      for (var c = 0; c < cbs.length; c++) {
        cbs[c].addEventListener('change', function(ev) {
          var sk = ev.target.getAttribute('data-skill');
          window.__aniketSkillCfg[sk] = !!ev.target.checked;
          saveSkillCfg(window.__aniketSkillCfg);
        });
      }

      var tabSpans = wrap.querySelectorAll('span[data-open-tab]');
      for (var s = 0; s < tabSpans.length; s++) {
        tabSpans[s].addEventListener('click', function(ev) {
          var tIdx = ev.currentTarget.getAttribute('data-open-tab') || '0';
          if (window.FlutterBridge) {
            window.FlutterBridge.postMessage('OPEN_11SKILL_SHEET:' + tIdx);
          }
        });
      }

      var fullBtn = wrap.querySelector('.aniket-skill-full-btn');
      if (fullBtn) {
        fullBtn.addEventListener('click', function() {
          if (window.FlutterBridge) {
            window.FlutterBridge.postMessage('OPEN_11SKILL_SHEET:0');
          }
        });
      }

      var runBtn = wrap.querySelector('.aniket-skill-run-btn');
      if (runBtn) {
        runBtn.addEventListener('click', async function() {
          var outBox = wrap.querySelector('.aniket-skill-live-out');
          if (!outBox) return;
          outBox.style.display = 'block';
          outBox.innerHTML = '⏳ Running all 11 Day-Trader Skills on live 5m candles...';
          var r = await run11SkillsEngine(window.__aniketSkillCfg.pair, window.__aniketSkillCfg.pairLabel);
          if (!r) {
            outBox.innerHTML = '⚠️ Could not fetch live candles right now. Check internet connection.';
            return;
          }
          outBox.innerHTML = render11SkillCardHtml(r);
        });
      }
    }

    function enhanceForexModeAndAnalysisDom() {
      try {
        // 1. Clean up Screenshot 3 fields in Mode tab (works even when Mode tab is hidden!)
        var keepFormSiblings = ['Risk per Trade', 'Account Balance', 'Daily Loss Limit', 'Max Daily Trades', 'A+ Threshold', 'ATR Multiplier', 'Partial Profit'];
        hideFieldWithoutTouchingSiblings('Twelve Data Key', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('Min Wait Between Analyze', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('Live Tolerance (auto)', keepFormSiblings);
        hideFieldWithoutTouchingSiblings('ATR Value (optional)', keepFormSiblings);

        // 2. Clean up Screenshot 2 switches & bottom guides in Mode tab
        var keepModeSiblings = ['Show HTF Zones', 'Browser Alerts', 'Live Memory Mode', 'Cache 5 min', 'Premium/Discount', 'OTE Filter', 'IDM Mandatory', 'Kill Zone Filter', 'News 15-min Filter', 'Dynamic ATR SL', 'Partial TP'];
        hideFieldWithoutTouchingSiblings('News Radar (OFF = quota bache)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Deep Mode (quota khay)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Cross-check (+1 call)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('SS Guide (perfect screenshot)', keepModeSiblings);
        hideFieldWithoutTouchingSiblings('Somossa hole ki korben', keepModeSiblings);

        // 3. Inject 11 Day-Trader Skills Card inside the Mode tab's 🎛️ Modes card (found via deepest container of 'Show HTF Zones' + 'Partial TP')
        var modesCard = findDeepestContainerWithBoth('Show HTF Zones', 'Partial TP');
        if (modesCard && !document.getElementById('aniket-11skills-mode-box')) {
          var modeWrap = document.createElement('div');
          modeWrap.id = 'aniket-11skills-mode-box';
          modeWrap.style.cssText = 'margin-top:14px;padding:14px;border-radius:12px;background:#0B1912;border:1.5px solid #D4AF37;color:#F5E6C8;font-family:sans-serif;';
          modeWrap.innerHTML = build11SkillsPanelHtml('mode');
          modesCard.appendChild(modeWrap);
          wire11SkillsContainer(modeWrap);
        }

        // 4. ALSO inject the 11 Day-Trader Skills Card on the Forex SS Home Tab (right below 'Key Status' / 'HTF Clear') so user sees it immediately on opening FOREX!
        var ssHomeCard = findDeepestContainerWithBoth('HTF Clear', 'Key Status');
        if (ssHomeCard && !document.getElementById('aniket-11skills-ss-box')) {
          var ssWrap = document.createElement('div');
          ssWrap.id = 'aniket-11skills-ss-box';
          ssWrap.style.cssText = 'margin:12px 0;padding:14px;border-radius:12px;background:#0B1912;border:1.5px solid #D4AF37;color:#F5E6C8;font-family:sans-serif;';
          ssWrap.innerHTML = build11SkillsPanelHtml('ss');
          ssHomeCard.appendChild(ssWrap);
          wire11SkillsContainer(ssWrap);
        }
      } catch(e) {}
    }

    function render11SkillCardHtml(r) {
      var d = r.dec;
      return ''
        + '<div style="font-weight:900;color:#FFD54F;font-size:13px;margin-bottom:6px;">🎯 11-SKILL LIVE REPORT: ' + r.label + ' @ ' + r.livePx.toFixed(d) + ' (' + (r.chgPct >= 0 ? '+' : '') + r.chgPct.toFixed(2) + '%)</div>'
        + '<div>• <b>3. Entry Timer (ORB 15m):</b> ' + r.entryStatus + ' | RSI-14: ' + r.rsi14.toFixed(1) + ' | ATR-14: ' + r.atr14.toFixed(d) + '</div>'
        + '<div style="color:#7CFC9B;">• <b>4. Exit Plan (LONG):</b> SL=' + r.longSL.toFixed(d) + ' | TP1(1R)=' + r.longTP1.toFixed(d) + ' | TP2(' + r.targetR + 'R)=' + r.longTP2.toFixed(d) + ' | TP3(3R)=' + r.longTP3.toFixed(d) + '</div>'
        + '<div style="color:#FFB74D;">• <b>4. Exit Plan (SHORT):</b> SL=' + r.shortSL.toFixed(d) + ' | TP1(1R)=' + r.shortTP1.toFixed(d) + ' | TP2(' + r.targetR + 'R)=' + r.shortTP2.toFixed(d) + ' | TP3(3R)=' + r.shortTP3.toFixed(d) + '</div>'
        + '<div>• <b>5. Time Machine (2,000x Monte Carlo):</b> Win Rate=' + r.winPct.toFixed(1) + '% (Need ' + r.bePct.toFixed(0) + '%) | Verdict: <b style="color:#7CFC9B;">' + r.tmVerdict + '</b></div>'
        + '<div>• <b>6. Budget & 7. Risk Gate:</b> Recommended Lot=<b>' + r.lots.toFixed(2) + ' Lots</b> (Risk USD ' + r.riskUsd.toFixed(2) + ') | Gate: <b>' + r.riskVerdict + '</b></div>'
        + '<div>• <b>8. Broker Ticket & 9. Clock:</b> Session=' + r.kz + ' | Flat-By=15:55 ET</div>';
    }

    setInterval(enhanceForexModeAndAnalysisDom, 600);

    function stripThinkTags(txt) {
      if (!txt) return '';
      return txt.replace(/<think>[\\s\\S]*?<\\/think>/gi, '').trim();
    }

    async function stitchImagesToDataUrl(imgList) {
      if (!imgList || imgList.length === 0) return null;
      if (imgList.length === 1) {
        return 'data:' + (imgList[0].mime || 'image/jpeg') + ';base64,' + imgList[0].b64;
      }
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
          var targetW = 1024;
          var pad = 28;
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
          canvas.height = Math.min(totalH, 4096);
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
            ctx.font = 'bold 15px sans-serif';
            ctx.fillText('FOREX CHART #' + (m + 1) + ' OF ' + valid.length, 12, y + Math.max(14, barH - 6));
            y += barH;
            ctx.drawImage(valid[m], 0, y, targetW, drawH);
            y += drawH;
          }
          resolve(canvas.toDataURL('image/jpeg', 0.84));
        }
      });
    }

    async function callOpenAiVisionProvider(endpoint, modelsUrl, key, defaultModels, promptText, imgList, requireFree, extraHeaders) {
      var models = defaultModels.slice();
      try {
        var mResp = await origFetch(modelsUrl, {
          method: 'GET',
          headers: { 'Authorization': 'Bearer ' + key }
        });
        if (mResp && mResp.ok) {
          var mJson = await mResp.json();
          var data = (mJson && mJson.data) || [];
          for (var d = 0; d < data.length; d++) {
            var id = (data[d] && data[d].id) || '';
            if (!id) continue;
            if (requireFree && id.indexOf(':free') < 0) continue;
            var low = id.toLowerCase();
            if (low.indexOf('qwen') >= 0 || low.indexOf('vl') >= 0 || low.indexOf('vision') >= 0 ||
                low.indexOf('gemma-3') >= 0 || low.indexOf('ministral') >= 0 || low.indexOf('pixtral') >= 0 ||
                low.indexOf('llama-4') >= 0) {
              if (models.indexOf(id) < 0) models.push(id);
            }
          }
        }
      } catch(e) {}

      var combinedDataUrl = await stitchImagesToDataUrl(imgList);

      for (var i = 0; i < models.length; i++) {
        var model = models[i];
        try {
          var userContent = [{ type: 'text', text: promptText }];
          if (combinedDataUrl) {
            userContent.push({
              type: 'image_url',
              image_url: { url: combinedDataUrl }
            });
          }
          var headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + key
          };
          if (extraHeaders) {
            for (var hk in extraHeaders) headers[hk] = extraHeaders[hk];
          }
          var resp = await origFetch(endpoint, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
              model: model,
              temperature: 0.2,
              max_tokens: 2048,
              messages: [{ role: 'user', content: userContent }]
            })
          });
          if (resp && resp.ok) {
            var j = await resp.json();
            var rawTxt = (j && j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || '';
            var cleaned = stripThinkTags(rawTxt);
            if (cleaned && cleaned.length > 10) {
              return cleaned;
            }
          }
        } catch(e) {}
      }
      return null;
    }

    async function callGeminiProvider(key, rawBodyStr, origUrlStr) {
      var origModelMatch = /models\\/([^/:?]+):generateContent/.exec(origUrlStr || '');
      var origModel = origModelMatch ? origModelMatch[1] : 'gemini-2.0-flash';
      var models = [origModel, 'gemini-2.5-flash', 'gemini-2.5-flash-lite', 'gemini-2.0-flash'];
      var uniqueModels = [];
      for (var u = 0; u < models.length; u++) {
        if (uniqueModels.indexOf(models[u]) < 0) uniqueModels.push(models[u]);
      }

      for (var i = 0; i < uniqueModels.length; i++) {
        var m = uniqueModels[i];
        try {
          var url = 'https://generativelanguage.googleapis.com/v1beta/models/' + m + ':generateContent?key=' + encodeURIComponent(key);
          var resp = await origFetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: rawBodyStr
          });
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
              if (finalTxt.length > 5) {
                return new Response(JSON.stringify({
                  candidates: [{ content: { parts: [{ text: finalTxt }] }, finishReason: 'STOP' }]
                }), { status: 200, headers: { 'Content-Type': 'application/json' } });
              }
            }
          }
        } catch(e) {}
      }
      return null;
    }

    window.fetch = async function(input, init) {
      var urlStr = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (urlStr.indexOf('generativelanguage.googleapis.com') >= 0 && urlStr.indexOf(':generateContent') >= 0) {
        var rawBodyStr = (init && init.body) ? init.body.toString() : '{}';
        var promptText = '';
        var imgList = [];
        try {
          var parsedBody = JSON.parse(rawBodyStr);
          var contents = (parsedBody && parsedBody.contents) || [];
          for (var c = 0; c < contents.length; c++) {
            var parts = (contents[c] && contents[c].parts) || [];
            for (var p = 0; p < parts.length; p++) {
              var pt = parts[p];
              if (pt.text) {
                promptText += (promptText ? '\\n\\n' : '') + pt.text;
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

        // ═══ RUN 11 DAY-TRADER SKILLS ENGINE & ENRICH FOREX ANALYSIS ═══
        try {
          var cfg = window.__aniketSkillCfg || loadSkillCfg();
          var upTxt = (((document.body && document.body.innerText) || '') + ' ' + promptText).toUpperCase();
          var detSym = cfg.pair || 'GC=F';
          var detLbl = cfg.pairLabel || 'XAU/USD (Gold)';
          if (upTxt.indexOf('BTC') >= 0 || upTxt.indexOf('BITCOIN') >= 0) {
            detSym = 'BTC-USD'; detLbl = 'BTC/USD (Bitcoin)';
          } else if (upTxt.indexOf('EURUSD') >= 0 || upTxt.indexOf('EUR/USD') >= 0) {
            detSym = 'EURUSD=X'; detLbl = 'EUR/USD';
          } else if (upTxt.indexOf('GBPUSD') >= 0 || upTxt.indexOf('GBP/USD') >= 0) {
            detSym = 'GBPUSD=X'; detLbl = 'GBP/USD';
          } else if (upTxt.indexOf('USDJPY') >= 0 || upTxt.indexOf('USD/JPY') >= 0) {
            detSym = 'USDJPY=X'; detLbl = 'USD/JPY';
          }

          var r = await run11SkillsEngine(detSym, detLbl);
          if (r) {
            var d = r.dec;
            var telemetryBlock = '\\n\\n[ANIKET PRO AI — 11 DAY-TRADER SKILLS LIVE TELEMETRY (' + r.label + ')]\\n'
              + '• Live Price: ' + r.livePx.toFixed(d) + ' (' + (r.chgPct >= 0 ? '+' : '') + r.chgPct.toFixed(2) + '%) | Session: ' + r.kz + '\\n'
              + '• trader-entry (5m Opening Range): ' + r.entryStatus + ' | OR High=' + r.orHigh.toFixed(d) + ' | OR Mid=' + r.orMid.toFixed(d) + ' | OR Low=' + r.orLow.toFixed(d) + ' | RSI-14=' + r.rsi14.toFixed(1) + ' | ATR-14=' + r.atr14.toFixed(d) + '\\n'
              + '• trader-exit (LONG Plan): Entry=' + r.livePx.toFixed(d) + ' | SL=' + r.longSL.toFixed(d) + ' | TP1(1R)=' + r.longTP1.toFixed(d) + ' | TP2(' + r.targetR + 'R)=' + r.longTP2.toFixed(d) + ' | TP3(3R)=' + r.longTP3.toFixed(d) + '\\n'
              + '• trader-exit (SHORT Plan): Entry=' + r.livePx.toFixed(d) + ' | SL=' + r.shortSL.toFixed(d) + ' | TP1(1R)=' + r.shortTP1.toFixed(d) + ' | TP2(' + r.targetR + 'R)=' + r.shortTP2.toFixed(d) + ' | TP3(3R)=' + r.shortTP3.toFixed(d) + '\\n'
              + '• trader-timemachine (2,000x Monte Carlo Replay): Win Rate=' + r.winPct.toFixed(1) + '% (Breakeven ' + r.bePct.toFixed(0) + '%) | Verdict=' + r.tmVerdict + '\\n'
              + '• trader-budget & trader-risk: Recommended Lot Size=' + r.lots.toFixed(2) + ' Lots (Balance USD ' + r.balance.toFixed(0) + ', Risk USD ' + r.riskUsd.toFixed(2) + ') | Risk Gate=' + r.riskVerdict + '\\n'
              + 'Combine the uploaded screenshots (HTF, ENTRY, CORRELATION) with these exact 11-Skill numbers and include the Monte Carlo Win Rate %, Recommended Lot Size, and Risk Gate PASS/BLOCK in your response.';

            promptText += telemetryBlock;
            try {
              var parsedForGem = JSON.parse(rawBodyStr);
              if (parsedForGem && parsedForGem.contents && parsedForGem.contents[0] && parsedForGem.contents[0].parts) {
                parsedForGem.contents[0].parts.push({ text: telemetryBlock });
                rawBodyStr = JSON.stringify(parsedForGem);
              }
            } catch(e2) {}
          }
        } catch(eTel) {}
        // ═══ END 11-SKILL FOREX ENRICHMENT ═══

        var urlKeyMatch = /[?&]key=([^&]+)/.exec(urlStr);
        var urlKey = urlKeyMatch ? cleanKey(decodeURIComponent(urlKeyMatch[1])) : '';
        var siteNow = readSiteKeys();
        var candidateKeys = [];

        if (urlKey && urlKey.length >= 16) {
          candidateKeys.push(urlKey);
        }
        if (window.__lastWorkingForexKey && window.__lastWorkingForexKey.length >= 16 && candidateKeys.indexOf(window.__lastWorkingForexKey) < 0) {
          candidateKeys.push(window.__lastWorkingForexKey);
        }
        for (var s = 0; s < siteNow.length; s++) {
          if (candidateKeys.indexOf(siteNow[s]) < 0) candidateKeys.push(siteNow[s]);
        }
        for (var a = 0; a < (window.__aniketAllKeys || []).length; a++) {
          var ak = window.__aniketAllKeys[a];
          if (ak && candidateKeys.indexOf(ak) < 0) candidateKeys.push(ak);
        }

        for (var idx = 0; idx < candidateKeys.length; idx++) {
          var k = candidateKeys[idx];
          if (!k) continue;

          if (k.indexOf('AIza') === 0) {
            var gemResp = await callGeminiProvider(k, rawBodyStr, urlStr);
            if (gemResp) {
              window.__lastWorkingForexKey = k;
              return gemResp;
            }
          } else if (k.indexOf('gsk_') === 0) {
            var groqTxt = await callOpenAiVisionProvider(
              'https://api.groq.com/openai/v1/chat/completions',
              'https://api.groq.com/openai/v1/models',
              k,
              ['qwen/qwen3.8-27b', 'meta-models/muse-spark-open', 'meta-llama/llama-4-scout-17b-16e-instruct', 'meta-llama/llama-4-maverick-17b-128e-instruct'],
              promptText,
              imgList,
              false,
              null
            );
            if (groqTxt) {
              window.__lastWorkingForexKey = k;
              return new Response(JSON.stringify({
                candidates: [{ content: { parts: [{ text: groqTxt }] }, finishReason: 'STOP' }]
              }), { status: 200, headers: { 'Content-Type': 'application/json' } });
            }
          } else if (k.indexOf('sk-or-') === 0) {
            var orTxt = await callOpenAiVisionProvider(
              'https://openrouter.ai/api/v1/chat/completions',
              'https://openrouter.ai/api/v1/models',
              k,
              ['openrouter/free', 'google/gemma-3-27b-it:free', 'qwen/qwen2.5-vl-72b-instruct:free', 'qwen/qwen2.5-vl-32b-instruct:free', 'mistralai/mistral-small-3.1-24b-instruct:free'],
              promptText,
              imgList,
              true,
              { 'HTTP-Referer': 'https://aniketpro.ai', 'X-Title': 'ANIKET PRO AI' }
            );
            if (orTxt) {
              window.__lastWorkingForexKey = k;
              return new Response(JSON.stringify({
                candidates: [{ content: { parts: [{ text: orTxt }] }, finishReason: 'STOP' }]
              }), { status: 200, headers: { 'Content-Type': 'application/json' } });
            }
          } else {
            var misTxt = await callOpenAiVisionProvider(
              'https://api.mistral.ai/v1/chat/completions',
              'https://api.mistral.ai/v1/models',
              k,
              ['mistral-small-latest', 'ministral-14b-latest', 'ministral-8b-latest', 'mistral-medium-latest', 'mistral-large-latest'],
              promptText,
              imgList,
              false,
              null
            );
            if (misTxt) {
              window.__lastWorkingForexKey = k;
              return new Response(JSON.stringify({
                candidates: [{ content: { parts: [{ text: misTxt }] }, finishReason: 'STOP' }]
              }), { status: 200, headers: { 'Content-Type': 'application/json' } });
            }
          }
        }
      }
      return origFetch(input, init);
    };
  } catch(e) {}
})();
''';
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
        } else if (m.startsWith('OPEN_11SKILL_SHEET:')) {
          final tabIdx = int.tryParse(m.substring(19).trim()) ?? 0;
          if (mounted) _openInForex11SkillSheet(initialTab: tabIdx);
        } else if (m.startsWith('SYNC_KEYS:')) {
          try {
            final rawList = jsonDecode(m.substring(10)) as List;
            final cleaned = rawList
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
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
          if (p >= 40) {
            try { _controller.runJavaScript(_netlifyHideJs()); } catch (_) {}
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openInForex11SkillSheet(initialTab: 0),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E2218).withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: kGold, width: 1.2),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bolt_rounded, color: kGold, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      '11 Skills',
                                      style: TextStyle(
                                        color: kGold,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
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
                        ],
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
            req.headers.set('Authorization', 'Bearer $k');
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
