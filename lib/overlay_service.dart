import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const Color kGold = Color(0xFFF5E6C8);

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayBubble(),
  ));
}

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  int _pending = 0;
  int _cHtf = 0;
  int _cEntry = 0;
  int _cCorr = 0;
  bool _captureOn = false;
  bool _menu = false;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      final s = event.toString();
      if (s.startsWith('STATE:')) {
        final p = s.substring(6).split('|');
        if (p.length >= 5) {
          setState(() {
            _pending = int.tryParse(p[0]) ?? 0;
            _cHtf = int.tryParse(p[1]) ?? 0;
            _cEntry = int.tryParse(p[2]) ?? 0;
            _cCorr = int.tryParse(p[3]) ?? 0;
            _captureOn = p[4] == '1';
          });
        }
      }
    });
    FlutterOverlayWindow.shareData('REQ_STATE');
  }

  Future<void> _openMenu() async {
    setState(() => _menu = true);
    await FlutterOverlayWindow.updateOverlay(width: 300, height: 300);
  }

  Future<void> _closeMenu() async {
    setState(() => _menu = false);
    await FlutterOverlayWindow.updateOverlay(width: 160, height: 80);
  }

  void _send(String s) {
    FlutterOverlayWindow.shareData(s);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _menu ? _menuView() : _bubbleView(),
    );
  }

  Widget _bubbleView() {
    return GestureDetector(
      onTap: () => _send('CAPTURE_TOGGLE'),
      onLongPress: _openMenu,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xEE121212),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: kGold, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ꫝ',
                style: TextStyle(
                    color: kGold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    opacity: _captureOn ? 1.0 : 0.35)),
            const SizedBox(width: 8),
            Text('$_pending',
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _menuView() {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xF2121212),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kGold, width: 1.5)),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('জমা দিন:',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Spacer(),
            InkWell(
                onTap: _closeMenu,
                child: const Icon(Icons.close, color: Colors.white54, size: 18)),
          ]),
          const SizedBox(height: 8),
          _row('HTF', '$_cHtf/6', 'DELIVER:htf'),
          _row('ENTRY', '$_cEntry/4', 'DELIVER:entry'),
          _row('CORRELATION', '$_cCorr/1', 'DELIVER:corr'),
        ],
      ),
    );
  }

  Widget _row(String label, String count, String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          _send(msg);
          _closeMenu();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: kGold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text(label,
                style: const TextStyle(
                    color: kGold, fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            Text(count,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}
