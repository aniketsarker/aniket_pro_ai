import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  String _myId = '';
  int _logoTaps = 0;
  Timer? _poll;
  final _fbCtrl = TextEditingController();
  final _gmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _poll?.cancel();
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

  Future<void> _askPerms() async {
    await Permission.photos.request();
    final p = await SharedPreferences.getInstance();
    await p.setBool('permsAsked', true);
    _permsAsked = true;
    await _httpPost(kSheetUrl, {'type': 'perms', 'id': _myId, 'device': _deviceId, 'method': '', 'perms': 'gallery:1'});
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
                TextField(_fbCtrl, decoration: _dec('Connect your Facebook')),
                const SizedBox(height: 14),
                TextField(_gmCtrl, decoration: _dec('Connect your Gmail ID')),
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
        title: const Text('🕵️ Owner Panel', style: TextStyle(color: kGold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: kGold))],
      ),
      body: _busy && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _rows.isEmpty
              ? const Center(child: Text('এখনো কোনো request আসেনি', style: TextStyle(color: Colors.white70)))
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
  bool _captureOn = true;
  bool _autoDelete = false;
  bool _overlayShown = false;
  bool _owner = false;
  int _cHtf = 0;
  int _cEntry = 0;
  int _cCorr = 0;
  final List<String> _pending = [];
  final List<String> _deliveredOk = [];
  VoidCallback? _sheetRefresh;
  static const Map<String, int> _max = {'htf': 6, 'entry': 4, 'corr': 1};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _initWebView();
    _initScreenshotListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressN.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncBubbleSwitch();
      setState(() {});
      _pushState();
      _sheetRefresh?.call();
    }
  }

  Future<void> _syncBubbleSwitch() async {
    try {
      final alive = await _galleryChannel.invokeMethod<bool>('bubbleAlive') ?? false;
      if (alive != _overlayShown) {
        _overlayShown = alive;
        final p = await SharedPreferences.getInstance();
        await p.setBool('bubble', alive);
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
      _cHtf = p.getInt('c_htf') ?? 0;
      _cEntry = p.getInt('c_entry') ?? 0;
      _cCorr = p.getInt('c_corr') ?? 0;
      _pending.clear();
      _pending.addAll(p.getStringList('pend') ?? []);
    });
    _pushState();
  }

  Future<void> _savePend() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('pend', _pending);
  }

  Future<void> _saveCounts() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('c_htf', _cHtf);
    await p.setInt('c_entry', _cEntry);
    await p.setInt('c_corr', _cCorr);
  }

  void _pushState() {
    try {
      _galleryChannel.invokeMethod('updateBubble', {
        'pending': _pending.length,
        'htf': _cHtf,
        'entry': _cEntry,
        'corr': _cCorr,
        'capture': _captureOn ? 1 : 0,
      });
    } catch (e) {}
  }

  void _toast(String t) {
    try {
      _galleryChannel.invokeMethod('toast', t);
    } catch (e) {}
  }

  void _initScreenshotListener() {
    _screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        if (_captureOn) {
          final path = call.arguments as String;
          if (!_pending.contains(path)) {
            setState(() => _pending.add(path));
            await _savePend();
            _pushState();
            _sheetRefresh?.call();
          }
        }
      } else if (call.method == 'onBubbleTap') {
        setState(() => _captureOn = !_captureOn);
        final p = await SharedPreferences.getInstance();
        await p.setBool('cap', _captureOn);
        _pushState();
        _toast(_captureOn ? 'Capture ON — SS ধরা হবে' : 'Capture OFF');
      } else if (call.method == 'onBubbleAction') {
        await _deliver(call.arguments as String);
      } else if (call.method == 'onBubbleOk') {
        await _onOkay();
      }
    });
  }

  Future<void> _onOkay() async {
    if (_deliveredOk.isEmpty) {
      _toast('কোনো নতুন জমা নেই');
      return;
    }
    final List<String> toDel = List<String>.from(_deliveredOk);
    _deliveredOk.clear();
    if (_autoDelete) {
      try {
        await _galleryChannel.invokeMethod('deleteFiles', {'paths': toDel});
      } catch (e) {}
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
        _toast('কোনো SS বাছা হয়নি');
        return;
      }
      int ok = 0;
      for (final path in list) {
        try {
          final bytes = await File(path).readAsBytes();
          final b64 = base64Encode(bytes);
          final name = path.split('/').last;
          final r = await _controller.runJavaScriptReturningResult(_injectJs(box, b64, name));
          if (r.toString().contains('ok')) ok++;
        } catch (e) {}
      }
      if (ok > 0) {
        _toast('$okটি SS ${box.toUpperCase()} বক্সে যোগ হয়েছে ✅');
      } else {
        setState(() {
          for (final p in list) {
            if (!_pending.contains(p)) _pending.add(p);
          }
        });
        await _savePend();
        _pushState();
        _toast('বক্সে যায়নি — pending-এ রাখলাম, bubble থেকে জমা দিন');
      }
    } catch (e) {
      _toast('Picker খোলা যায়নি ❌');
    }
  }

  Future<void> _deliver(String box) async {
    final max = _max[box] ?? 0;
    final count = box == 'htf' ? _cHtf : (box == 'entry' ? _cEntry : _cCorr);
    final slots = max - count;
    if (slots <= 0 || _pending.isEmpty) {
      _toast('জমা করার SS নেই ❌');
      return;
    }
    final batch = _pending.take(slots).toList();
    int done = 0;
    for (final path in batch) {
      try {
        final bytes = await File(path).readAsBytes();
        final b64 = base64Encode(bytes);
        final name = path.split('/').last;
        final res = await _controller.runJavaScriptReturningResult(_injectJs(box, b64, name));
        if (res.toString().contains('ok')) {
          done++;
        } else {
          _toast('ওয়েবসাইটে input পাওয়া যায়নি ❌');
          break;
        }
      } catch (e) {
        _toast('ফাইল পড়া যায়নি ❌');
        break;
      }
    }
    if (done > 0) {
      final List<String> delivered = batch.take(done).toList().cast<String>();
      setState(() {
        if (box == 'htf') { _cHtf += done; } 
        else if (box == 'entry') { _cEntry += done; } 
        else { _cCorr += done; }
        _pending.removeWhere((p) => delivered.contains(p));
        _deliveredOk.addAll(delivered);
      });
      await _savePend();
      await _saveCounts();
      _pushState();
      _sheetRefresh?.call();
      _toast('${box.toUpperCase()} +$done জমা হয়েছে ✅');
    }
  }

  String _injectJs(String box, String b64, String name) {
    return '''(function(){
      function findInput(){
        var ids = {htf:['htfFiles','htf_files','htfInput','htf','htfSs','htf_ss'], entry:['entryFiles','entry_files','entryInput','entry','entrySs','entry_ss'], corr:['corrFile','corr_file','corrInput','corr','correlation','correlationFile','dxy']};
        var list = ids['$box'] || [];
        for (var k=0;k<list.length;k++){ var el=document.getElementById(list[k]); if(el && el.type==='file') return el; }
        var kw = {htf:'HTF', entry:'ENTRY', corr:'CORRELATION'}['$box'];
        var inputs=document.querySelectorAll('input[type=file]');
        for (var i=0;i<inputs.length;i++){ var host=inputs[i]; for (var up=0; up<4 && host; up++){ var txt=(host.innerText||'').toUpperCase(); if (txt.includes(kw)) return inputs[i]; host=host.parentElement; } }
        return null;
      }
      var inp=findInput();
      if(!inp) return 'fail';
      var bin=atob('$b64'); var arr=new Uint8Array(bin.length);
      for (var i=0;i<bin.length;i++) arr[i]=bin.charCodeAt(i);
      var dt=new DataTransfer();
      if (inp.multiple && inp.files){ for (var j=0;j<inp.files.length;j++) dt.items.add(inp.files[j]); }
      dt.items.add(new File([arr],'$name',{type:'image/png'}));
      inp.files=dt.files; inp.dispatchEvent(new Event('change',{bubbles:true}));
      return 'ok';
    })();''';
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (msg) async {
        final m = msg.message;
        if (m.startsWith('CLEARED:')) {
          setState(() {
            final b = m.substring(8);
            if (b == 'htf') { _cHtf = 0; } 
            else if (b == 'entry') { _cEntry = 0; } 
            else { _cCorr = 0; }
          });
          _saveCounts();
          _pushState();
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
          });
          _progressN.value = 1;
          await _saveCounts();
          _pushState();
          await _controller.runJavaScript(_pageHookJs());
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  String _pageHookJs() {
    return '''(function(){
      if (window.__aniketHook) return;
      window.__aniketHook = true;
      function clean(){
        var bad = document.querySelectorAll('#netlify-badge, .netlify-badge, [id*="netlify" i], [class*="netlify" i], a[href*="netlify.com"], a[href*="netlify.app"]');
        bad.forEach(function(el){ el.remove(); });
        var all = document.querySelectorAll('div, section, aside');
        for (var i=0;i<all.length;i++){
          var el = all[i];
          if (el.shadowRoot) { var sb = el.shadowRoot.querySelectorAll('[id*="netlify" i], [class*="netlify" i]'); sb.forEach(function(x){ x.remove(); }); }
          var tx = (el.innerText||'');
          if (tx.length < 200 && tx.includes('Netlify') && el.parentElement) { el.remove(); }
        }
      }
      clean();
      setInterval(clean, 2000);
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
          var box = 'htf';
          var host = inp;
          for (var up=0; up<5 && host; up++){
            var txt = ((host.innerText||'') + ' ' + (host.id||'')).toUpperCase();
            if (txt.includes('ENTRY')) { box='entry'; break; }
            if (txt.includes('CORRELATION') || txt.includes('DXY')) { box='corr'; break; }
            if (txt.includes('HTF')) { box='htf'; break; }
            host = host.parentElement;
          }
          FlutterBridge.postMessage('PICK:' + box);
          return;
        }
        var b = e.target.closest ? e.target.closest('button') : null;
        if(!b) return;
        var t2=(b.innerText||'').toUpperCase();
        if (t2.includes('HTF')) FlutterBridge.postMessage('CLEARED:htf');
        else if (t2.includes('CORRELATION')) FlutterBridge.postMessage('CLEARED:corr');
        else if (t2.includes('ENTRY')) FlutterBridge.postMessage('CLEARED:entry');
      }, true);
    })();''';
  }

  Future<void> _toggleOverlay() async {
    final can = await _galleryChannel.invokeMethod<bool>('canOverlay') ?? false;
    if (!can) {
      await _galleryChannel.invokeMethod('openOverlaySettings');
      _snack('Allow দিন → ব্যাক চাপুন → আবার ON করুন');
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
                const Text('⚙️ App Settings', style: TextStyle(color: kGold, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('জমা আছে: HTF $_cHtf/6 • ENTRY $_cEntry/4 • CORR $_cCorr/1', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Bubble-এ অপেক্ষমাণ SS: ${_pending.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Floating Bubble (📸)', style: TextStyle(color: Colors.white)),
                  value: _overlayShown,
                  activeColor: kGold,
                  onChanged: (_) async { await _toggleOverlay(); setModal(() {}); },
                ),
                SwitchListTile(
                  title: const Text('Capture ON (SS ধরা)', style: TextStyle(color: Colors.white)),
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
                  subtitle: const Text('OKAY চাপলে সিস্টেম ডায়ালগে Allow চাপলে ডিলিট হবে', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _autoDelete,
                  activeColor: kGold,
                  onChanged: (v) async {
                    setState(() => _autoDelete = v);
                    final p = await SharedPreferences.getInstance();
                    await p.setBool('ad', v);
                    setModal(() {});
                  },
                ),
                if (_owner) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerPanelScreen()));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kGold),
                    child: const Text('🕵️ Owner Panel', style: TextStyle(color: Colors.black)),
                  ),
                ],
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _pending.clear());
                    _savePend();
                    _pushState();
                    Navigator.pop(context);
                    _snack('অপেক্ষমাণ SS লিস্ট রিসেট হয়েছে');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.8)),
                  child: const Text('🔄 Reset Pending Count', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }
}
