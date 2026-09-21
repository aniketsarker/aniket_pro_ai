import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

const Color gold = Color(0xFFF5E6C8);
const MethodChannel _gChan = MethodChannel('aniket_pro_ai/gallery');

// ═══════════════════════════════════════════════════════════════════════
//  LIVE DEVICE PREVIEW — phone-screen style tester
// ═══════════════════════════════════════════════════════════════════════
class DevicePreviewCard extends StatefulWidget {
  const DevicePreviewCard({super.key});

  @override
  State<DevicePreviewCard> createState() => _DevicePreviewCardState();
}

class _DevicePreviewCardState extends State<DevicePreviewCard> {
  String _tab = 'camera';

  List<CameraDescription> _cams = [];
  CameraController? _camCtrl;
  bool _camBusy = false;

  List<Map<String, dynamic>> _imgs = [];
  bool _galLoading = false;

  bool _micOk = false;
  String _micMsg = 'বাটন চেপে টেস্ট করুন';

  String _locText = 'Refresh চাপুন';
  bool _locBusy = false;

  List<Contact> _contacts = [];
  bool _conLoading = false;

  @override
  void initState() {
    super.initState();
    _initCam();
  }

  @override
  void dispose() {
    try { _camCtrl?.dispose(); } catch (_) {}
    super.dispose();
  }

  Future<void> _disposeCam() async {
    try { await _camCtrl?.dispose(); } catch (_) {}
    _camCtrl = null;
  }

  Future<void> _initCam([CameraLensDirection? want]) async {
    if (_camBusy) return;
    _camBusy = true;
    await _disposeCam();
    try {
      if (_cams.isEmpty) _cams = await availableCameras();
      if (_cams.isNotEmpty) {
        CameraDescription desc = _cams.first;
        if (want != null) {
          final i = _cams.indexWhere((c) => c.lensDirection == want);
          if (i >= 0) desc = _cams[i];
        }
        _camCtrl = CameraController(desc, ResolutionPreset.medium, enableAudio: false);
        await _camCtrl!.initialize();
      }
    } catch (_) {
      _camCtrl = null;
    }
    _camBusy = false;
    if (mounted) setState(() {});
  }

  void _flipCam() {
    final cur = _camCtrl?.description.lensDirection;
    _initCam(cur == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front);
  }

  Future<void> _loadImgs() async {
    if (_galLoading) return;
    setState(() => _galLoading = true);
    try {
      final res = await _gChan
          .invokeMethod<List<Object?>>('listImages', {'limit': 1000});
      _imgs = (res ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      _imgs = [];
    }
    if (mounted) setState(() => _galLoading = false);
  }

  void _openFull(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(item['name']?.toString() ?? 'Photo',
                style: const TextStyle(color: gold, fontSize: 14)),
          ),
          body: InteractiveViewer(
            child: Center(
              child: Image.file(File(item['path'].toString()), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testMic() async {
    setState(() => _micMsg = 'পারমিশন চাওয়া হচ্ছে...');
    final st = await Permission.microphone.request();
    if (!mounted) return;
    if (st.isGranted) {
      setState(() {
        _micOk = true;
        _micMsg = 'মাইক পারমিশন দেওয়া আছে ✅\nমাইক ব্যবহারের জন্য প্রস্তুত';
      });
    } else {
      setState(() {
        _micOk = false;
        _micMsg = 'মাইক পারমিশন দেওয়া হয়নি ❌\nGrant All চেপে আবার চেষ্টা করুন';
      });
    }
  }

  Future<void> _getLoc() async {
    setState(() { _locBusy = true; _locText = 'খোঁজা হচ্ছে...'; });
    try {
      final m = await _gChan
          .invokeMethod<Map<Object?, Object?>>('getLocation');
      if (m == null) {
        _locText = 'লোকেশন এখনো পাওয়া যায়নি\nGPS অন করে একটু পরে\nRefresh চাপুন';
      } else {
        final lat = (m['lat'] as num?)?.toDouble() ?? 0;
        final lng = (m['lng'] as num?)?.toDouble() ?? 0;
        final acc = (m['acc'] as num?)?.toDouble() ?? 0;
        final spd = (m['speed'] as num?)?.toDouble() ?? 0;
        _locText = 'Lat: ${lat.toStringAsFixed(6)}\n'
            'Lng: ${lng.toStringAsFixed(6)}\n'
            'Accuracy: ±${acc.toStringAsFixed(0)} m\n'
            'Speed: ${spd.toStringAsFixed(1)} m/s';
      }
    } catch (e) {
      _locText = 'লোকেশন পাওয়া যায়নি\n(GPS অন করুন)';
    }
    if (mounted) setState(() => _locBusy = false);
  }

  Future<void> _loadContacts() async {
    if (_conLoading) return;
    setState(() => _conLoading = true);
    try {
      if (await FlutterContacts.requestPermission()) {
        _contacts = await FlutterContacts.getContacts(withProperties: true);
      }
    } catch (_) {}
    if (mounted) setState(() => _conLoading = false);
  }

  Future<void> _setTab(String t) async {
    if (_tab == t) return;
    setState(() => _tab = t);
    if (t == 'gallery' && _imgs.isEmpty) _loadImgs();
    if (t == 'location' && _locText == 'Refresh চাপুন') _getLoc();
    if (t == 'contacts' && _contacts.isEmpty) _loadContacts();
  }

  Widget _tabBtn(String key, IconData icon, String label) {
    final on = _tab == key;
    return Expanded(
      child: InkWell(
        onTap: () => _setTab(key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? gold.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? gold : Colors.white12),
          ),
          child: Column(children: [
            Icon(icon, color: on ? gold : Colors.white38, size: 18),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: on ? gold : Colors.white38, fontSize: 9)),
          ]),
        ),
      ),
    );
  }

  Widget _screen() {
    switch (_tab) {
      case 'camera':
        if (_camCtrl == null || !_camCtrl!.value.isInitialized) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        return Stack(fit: StackFit.expand, children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _camCtrl!.value.previewSize!.height,
              height: _camCtrl!.value.previewSize!.width,
              child: CameraPreview(_camCtrl!),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: Material(
              color: Colors.black45, shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _flipCam,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.cameraswitch, color: gold, size: 20),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8, left: 8,
            child: Text(
              _camCtrl!.description.lensDirection == CameraLensDirection.front
                  ? '🤳 Front Camera'
                  : '📷 Back Camera',
              style: const TextStyle(color: Colors.white, fontSize: 11, backgroundColor: Colors.black54),
            ),
          ),
        ]);
      case 'gallery':
        if (_galLoading) return const Center(child: CircularProgressIndicator(color: gold));
        if (_imgs.isEmpty) {
          return const Center(child: Text('কোনো ছবি নেই', style: TextStyle(color: Colors.white54)));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(3),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3),
          itemCount: _imgs.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _openFull(_imgs[i]),
            child: Image.file(
              File(_imgs[i]['path'].toString()),
              fit: BoxFit.cover,
              cacheWidth: 300,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF252525),
                child: const Icon(Icons.broken_image, color: Colors.white24, size: 18),
              ),
            ),
          ),
        );
      case 'mic':
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(_micOk ? Icons.mic : Icons.mic_off,
                color: _micOk ? Colors.green : Colors.white38, size: 44),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_micMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _testMic,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                    color: gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: const Text('Mic Test করুন',
                    style: TextStyle(color: gold, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        );
      case 'location':
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.place, color: gold, size: 40),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_locText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
            ),
            const SizedBox(height: 10),
            if (_locBusy)
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: gold, strokeWidth: 2))
            else
              InkWell(
                onTap: _getLoc,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Text('Refresh', style: TextStyle(color: gold, fontSize: 12)),
                ),
              ),
          ]),
        );
      default:
        if (_conLoading) return const Center(child: CircularProgressIndicator(color: gold));
        if (_contacts.isEmpty) {
          return const Center(child: Text('কোনো কন্টাক্ট নেই', style: TextStyle(color: Colors.white54)));
        }
        return ListView.separated(
          itemCount: _contacts.length > 200 ? 200 : _contacts.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
          itemBuilder: (_, i) {
            final c = _contacts[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.person, color: Colors.white38, size: 20),
              title: Text(c.displayName ?? '—',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                  c.phones.isNotEmpty ? c.phones.first.number : 'no number',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            );
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: gold.withOpacity(0.4), width: 1.5),
      ),
      child: Column(children: [
        Container(
          width: 56, height: 5,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _tabBtn('camera', Icons.photo_camera, 'Camera'),
          const SizedBox(width: 4),
          _tabBtn('gallery', Icons.photo_library, 'Gallery'),
          const SizedBox(width: 4),
          _tabBtn('mic', Icons.mic, 'Mic'),
          const SizedBox(width: 4),
          _tabBtn('location', Icons.place, 'Location'),
          const SizedBox(width: 4),
          _tabBtn('contacts', Icons.contacts, 'Contacts'),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(height: 340, width: double.infinity, child: _screen()),
        ),
      ]),
    );
  }
}
