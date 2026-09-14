import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const Color kGold = Color(0xFFF5E6C8);
const Color kBg = Color(0xFF121212);
const String kUrl = 'https://aniketsarker1726.netlify.app';
const MethodChannel _galleryChannel = MethodChannel('aniket_pro_ai/gallery');
const MethodChannel _screenshotChannel = MethodChannel('aniket_pro_ai/screenshot');

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
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [Permission.photos, Permission.storage, Permission.systemAlertWindow].request();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainWebViewScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', width: 150, height: 150),
            const SizedBox(height: 16),
            const Text('ANIKET PRO AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kGold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Text('Loading SMC Engine...', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: kGold),
          ],
        ),
      ),
    );
  }
}

class MainWebViewScreen extends StatefulWidget {
  const MainWebViewScreen({super.key});
  @override
  State<MainWebViewScreen> createState() => _MainWebViewScreenState();
}

class _MainWebViewScreenState extends State<MainWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _firstLoad = true;
  double _progress = 0;
  bool _captureOn = true;
  bool _autoDelete = false;
  bool _overlayShown = false;
  int _cHtf = 0;
  int _cEntry = 0;
  int _cCorr = 0;
  final List<String> _pending = [];
  static const Map<String, int> _max = {'htf': 6, 'entry': 4, 'corr': 1};

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _initWebView();
    _initOverlayListener();
    _initScreenshotListener();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _captureOn = p.getBool('cap') ?? true;
      _autoDelete = p.getBool('ad') ?? false;
      _cHtf = p.getInt('c_htf') ?? 0;
      _cEntry = p.getInt('c_entry') ?? 0;
      _cCorr = p.getInt('c_corr') ?? 0;
    });
    _pushState();
  }

  Future<void> _saveCounts() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('c_htf', _cHtf);
    await p.setInt('c_entry', _cEntry);
    await p.setInt('c_corr', _cCorr);
  }

  void _pushState() {
    FlutterOverlayWindow.shareData('STATE:${_pending.length}|$_cHtf|$_cEntry|$_cCorr|${_captureOn ? 1 : 0}');
  }

  void _initScreenshotListener() {
    _screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot' && _captureOn) {
        final path = call.arguments as String;
        if (!_pending.contains(path)) {
          setState(() => _pending.add(path));
          _pushState();
        }
      }
    });
  }

  void _initOverlayListener() {
    FlutterOverlayWindow.overlayListener.listen((event) async {
      final s = event.toString();
      if (s == 'CAPTURE_TOGGLE') {
        setState(() => _captureOn = !_captureOn);
        final p = await SharedPreferences.getInstance();
        await p.setBool('cap', _captureOn);
        _pushState();
      } else if (s == 'REQ_STATE') {
        _pushState();
      } else if (s.startsWith('DELIVER:')) {
        await _deliver(s.substring(8));
      }
    });
  }

  Future<void> _deliver(String box) async {
    final max = _max[box] ?? 0;
    final count = box == 'htf' ? _cHtf : (box == 'entry' ? _cEntry : _cCorr);
    final slots = max - count;
    if (slots <= 0 || _pending.isEmpty) {
      FlutterOverlayWindow.shareData('TOAST:কিছু জমা করার নেই');
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
          FlutterOverlayWindow.shareData('TOAST:ওয়েবসাইটে input পাওয়া যায়নি');
          break;
        }
      } catch (e) {
        FlutterOverlayWindow.shareData('TOAST:ফাইল পড়া যায়নি');
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
      });
      await _saveCounts();
      _pushState();
      if (_autoDelete) {
        try {
          await _galleryChannel.invokeMethod('deleteFiles', {'paths': delivered});
        } catch (e) {}
      }
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
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (msg) {
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
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p / 100);
        },
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) async {
          setState(() {
            _isLoading = false;
            _firstLoad = false;
            _progress = 1;
            _cHtf = 0;
            _cEntry = 0;
            _cCorr = 0;
          });
          await _saveCounts();
          _pushState();
          await _controller.runJavaScript(_pageHookJs());
        },
      ))
      ..loadRequest(Uri.parse(kUrl));
  }

  String _pageHookJs() {
    return '''(function(){
      var badges = document.querySelectorAll('a[href*="netlify"], div[id*="netlify"], .netlify-badge');
      badges.forEach(function(el){ el.remove(); });
      var all = document.querySelectorAll('*');
      for (var i=0;i<all.length;i++){ if (all[i].innerText && all[i].innerText.includes('Powered by Netlify')){ all[i].style.display='none'; } }
      document.addEventListener('click', function(e){
        var b = e.target.closest ? e.target.closest('button') : null;
        if(!b) return;
        var t=(b.innerText||'').toUpperCase();
        if (t.includes('HTF')) FlutterBridge.postMessage('CLEARED:htf');
        else if (t.includes('CORRELATION')) FlutterBridge.postMessage('CLEARED:corr');
        else if (t.includes('ENTRY')) FlutterBridge.postMessage('CLEARED:entry');
      }, true);
    })();''';
  }

  Future<void> _toggleOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      final ok = await FlutterOverlayWindow.requestPermission();
      if (ok != true) {
        _snack('Settings খুলবে → "Display over other apps" → ANIKET PRO AI → Allow দিন → তারপর ব্যাক চাপুন');
        return;
      }
    }
    if (_overlayShown) { await FlutterOverlayWindow.closeOverlay(); _overlayShown = false; } 
    else {
      await FlutterOverlayWindow.showOverlay(width: 160, height: 80, enableDrag: true, alignment: OverlayAlignment.topRight, overlayTitle: 'ANIKET PRO AI', overlayContent: '');
      _overlayShown = true;
      _pushState();
    }
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
            if (_isLoading && !_firstLoad)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  color: kGold,
                  backgroundColor: Colors.transparent,
                ),
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
        builder: (context, setModal) => Padding(
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
                title: const Text('Floating Bubble (ꫝ)', style: TextStyle(color: Colors.white)),
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
                subtitle: const Text('জমা হওয়ার পর সিস্টেম ডায়ালগে Allow চাপলে ডিলিট হবে', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                onPressed: () {
                  setState(() => _pending.clear());
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
        ),
      ),
    );
  }
}
