import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core.dart';

const MethodChannel binaryChannel = MethodChannel('aniket_pro_ai/binary');

// ── Pocket Option এর সব market ──
const List<String> kBinaryPairs = [
  'EUR/USD', 'GBP/USD', 'USD/JPY', 'AUD/USD', 'USD/CAD', 'USD/CHF', 'NZD/USD',
  'EUR/GBP', 'EUR/JPY', 'GBP/JPY', 'AUD/JPY', 'EUR/AUD', 'EUR/CAD', 'EUR/CHF',
  'GBP/AUD', 'GBP/CAD', 'GBP/CHF', 'AUD/CAD', 'AUD/CHF', 'AUD/NZD', 'CAD/CHF',
  'CAD/JPY', 'CHF/JPY', 'NZD/CAD', 'NZD/CHF', 'NZD/JPY',
  'BTC/USD', 'ETH/USD', 'LTC/USD', 'XRP/USD', 'SOL/USD', 'DOGE/USD', 'BNB/USD',
  'ADA/USD', 'TRX/USD', 'DOT/USD', 'BCH/USD', 'LINK/USD',
  'Gold/USD', 'Silver/USD', 'WTI Oil', 'Brent Oil',
  'Apple', 'Tesla', 'Amazon', 'Google', 'Meta', 'Microsoft',
  'S&P 500', 'Nasdaq 100', 'Dow Jones',
  'EUR/USD (OTC)', 'GBP/USD (OTC)', 'USD/JPY (OTC)', 'AUD/USD (OTC)',
  'NZD/USD (OTC)', 'USD/CAD (OTC)', 'CAD/CHF (OTC)', 'EUR/GBP (OTC)',
  'BTC/USD (OTC)', 'ETH/USD (OTC)', 'Gold/USD (OTC)',
];

const List<String> kBinaryTimes = ['1m', '2m', '3m', '5m', '15m', '30m', '1h'];

// ── FIX: একাধিক model চেষ্টা করবে ──
const List<String> kGeminiModels = [
  'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-flash-latest',
];

int _periodSec(String t) {
  switch (t) {
    case '2m': return 120;
    case '3m': return 180;
    case '5m': return 300;
    case '15m': return 900;
    case '30m': return 1800;
    case '1h': return 3600;
    default: return 60;
  }
}

String _fmtRem(int s) {
  final m = s ~/ 60;
  final ss = s % 60;
  return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
}

// ═══════════════════════════════════════════════════════════════════
//  BINARY SIGNAL SCREEN (manual upload + exact error display)
// ═══════════════════════════════════════════════════════════════════
class BinarySignalScreen extends StatefulWidget {
  const BinarySignalScreen({super.key});

  @override
  State<BinarySignalScreen> createState() => _BinarySignalScreenState();
}

class _BinarySignalScreenState extends State<BinarySignalScreen> {
  String _pair = kBinaryPairs[0];
  String _time = '1m';
  String _dir = '—';
  int _conf = 0;
  String _reason = 'Screenshot nao → Analyze Now → ss choose koro';
  List<String> _history = [];
  List<String> _keys = [];
  bool _floatOn = false;
  bool _busy = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    binaryChannel.setMethodCallHandler((call) async {
      if (call.method == 'onBinaryResult') {
        final m = Map<String, Object?>.from(call.arguments as Map);
        _onResult(m);
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _history = p.getStringList('bin_hist') ?? [];
      _keys = (p.getStringList('bin_keys') ?? []);
      _floatOn = p.getBool('bin_float') ?? false;
      _pair = p.getString('bin_pair') ?? _pair;
      _time = p.getString('bin_time') ?? _time;
    });
  }

  Future<void> _saveHist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('bin_hist', _history);
  }

  void _onResult(Map m) {
    final dir = (m['dir'] ?? 'WAIT').toString();
    final conf = (m['conf'] as num?)?.toInt() ?? 0;
    if (dir == 'STATE') {
      if (mounted) setState(() => _floatOn = (conf == 1));
      return;
    }
    final reason = (m['reason'] ?? '').toString();
    if (reason.startsWith('fail:')) return; // fail history তে যাবে না
    final pair = (m['pair'] ?? _pair).toString();
    final time = (m['time'] ?? _time).toString();
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _conf = conf;
      _reason = reason.isEmpty ? '—' : reason;
      _history.insert(0,
          '${dir == 'UP' ? '⬆️' : dir == 'DOWN' ? '⬇️' : '⏸️'} $conf% $pair $time $hh:$mm');
      if (_history.length > 5) _history = _history.sublist(0, 5);
    });
    _saveHist();
  }

  void _applyResult(String dir, int conf, String reason) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _conf = conf;
      _reason = reason.isEmpty ? '—' : reason;
      _history.insert(0,
          '${dir == 'UP' ? '⬆️' : dir == 'DOWN' ? '⬇️' : '⏸️'} $conf% $_pair $_time $hh:$mm');
      if (_history.length > 5) _history = _history.sublist(0, 5);
    });
    _saveHist();
  }

  int get _rem {
    final p = _periodSec(_time);
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return p - (epoch % p);
  }

  Future<void> _keysDialog() async {
    final c = TextEditingController(text: _keys.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Gemini Keys', style: TextStyle(color: kGold)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            maxLines: 8,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'proti line e ekta key paste koro',
              hintStyle: TextStyle(color: Colors.white24),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Save', style: TextStyle(color: kGold))),
        ],
      ),
    );
    if (ok == true) {
      final list = c.text
          .split(RegExp(r'[\n,;\s]+'))
          .where((s) => s.trim().length > 20)
          .toList();
      final p = await SharedPreferences.getInstance();
      await p.setStringList('bin_keys', list);
      setState(() => _keys = list);
    }
  }

  // ═══ MANUAL UPLOAD (guaranteed path) ═══
  Future<void> _pickAndAnalyze() async {
    if (_busy) return;
    if (_keys.isEmpty) {
      await _keysDialog();
      if (_keys.isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      final res = await galleryChannel
          .invokeMethod<List<Object?>>('pickFiles', {'max': 1});
      final list = (res ?? []).map((e) => e.toString()).toList();
      if (list.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      var bytes = await File(list.first).readAsBytes();
      try {
        final comp = await galleryChannel
            .invokeMethod<Uint8List>('compress', {'bytes': bytes, 'maxKB': 700});
        if (comp != null && comp.isNotEmpty) bytes = comp;
      } catch (_) {}
      final b64 = base64Encode(bytes);
      final r = await _geminiVision(b64);
      final reason = (r['reason'] ?? '').toString();
      if (reason.startsWith('fail:')) {
        // FIX: fail hole card এ exact error, history তে নয়
        if (mounted) {
          setState(() {
            _dir = '—';
            _conf = 0;
            _reason = reason;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(reason),
              backgroundColor: const Color(0xFF2A2A2A),
              duration: const Duration(seconds: 6)));
        }
      } else {
        _applyResult(
            (r['dir'] ?? 'WAIT').toString(),
            (r['conf'] as num?)?.toInt() ?? 0,
            reason);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fail: $e'), backgroundColor: const Color(0xFF2A2A2A)));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── FIX: multi-model + exact error ──
  Future<Map<String, dynamic>> _geminiVision(String b64) async {
    final prompt = 'You are a professional binary options trader. Look at this '
        'trading chart screenshot carefully (candles, trend, support/resistance). '
        'Predict the NEXT candle direction for $_pair on $_time timeframe. '
        'Reply ONLY with JSON like: {"dir":"UP","conf":72,"reason":"short Banglish reason"} '
        'dir must be UP or DOWN or WAIT. If chart is unclear or not a trading chart, use WAIT.';
    String lastErr = '';
    for (final key in _keys) {
      for (final model in kGeminiModels) {
        try {
          final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
          final req = await c.postUrl(Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key'));
          req.headers.set('Content-Type', 'application/json');
          req.write(jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
                  }
                ]
              }
            ]
          }));
          final res = await req.close().timeout(const Duration(seconds: 30));
          final s = await res.transform(utf8.decoder).join();
          c.close();
          if (res.statusCode == 200) {
            final j = jsonDecode(s);
            final parts = j['candidates'][0]['content']['parts'] as List;
            String text = '';
            for (final p in parts) {
              text += (p['text'] ?? '').toString();
            }
            final a = text.indexOf('{');
            final z = text.lastIndexOf('}');
            if (a >= 0 && z > a) {
              return Map<String, dynamic>.from(
                  jsonDecode(text.substring(a, z + 1)));
            }
            return {'dir': 'WAIT', 'conf': 0, 'reason': 'parse fail'};
          } else {
            lastErr = 'fail: HTTP ${res.statusCode} — key invalid/quota/model block';
          }
        } catch (e) {
          lastErr = 'fail: net — ${e.toString().split('\n').first}';
        }
      }
    }
    return {
      'dir': 'WAIT',
      'conf': 0,
      'reason': lastErr.isEmpty ? 'fail: key nei — key boshao' : lastErr
    };
  }

  Future<void> _toggleFloat() async {
    if (_keys.isEmpty) {
      await _keysDialog();
      if (_keys.isEmpty) return;
    }
    final on = !_floatOn;
    try {
      if (on) {
        await binaryChannel.invokeMethod('startFloat', {'keys': _keys});
      } else {
        await binaryChannel.invokeMethod('stopFloat', null);
      }
      final p = await SharedPreferences.getInstance();
      await p.setBool('bin_float', on);
      setState(() => _floatOn = on);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Overlay permission din age'),
          backgroundColor: Color(0xFF2A2A2A)));
    }
  }

  Color _dirColor() {
    if (_dir == 'UP') return const Color(0xFF0F9D58);
    if (_dir == 'DOWN') return const Color(0xFFD93025);
    return Colors.white38;
  }

  IconData _dirIcon() {
    if (_dir == 'UP') return Icons.arrow_upward_rounded;
    if (_dir == 'DOWN') return Icons.arrow_downward_rounded;
    return Icons.remove_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kGold.withOpacity(0.4)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _pair,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: kBinaryPairs
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() => _pair = v);
                        final p = await SharedPreferences.getInstance();
                        await p.setString('bin_pair', v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kGold.withOpacity(0.4)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _time,
                    dropdownColor: const Color(0xFF1A1A2E),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: kBinaryTimes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _time = v);
                      final p = await SharedPreferences.getInstance();
                      await p.setString('bin_time', v);
                    },
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _dirColor().withOpacity(0.6), width: 1.5),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_dirIcon(), color: _dirColor(), size: 44),
                  const SizedBox(width: 10),
                  Text(_dir,
                      style: TextStyle(
                          color: _dirColor(),
                          fontSize: 34,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 14),
                  Text('|  $_conf%',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 14),
                  Text('|  ${_fmtRem(_rem)} baki',
                      style: const TextStyle(
                          color: kGold,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text('$_pair  •  $_time',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Text(_reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickAndAnalyze,
                icon: const Icon(Icons.folder_open_rounded, size: 22),
                label: Text(
                    _busy ? 'Analysis cholche...' : 'Analyze Now — ss choose koro',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold.withOpacity(0.25),
                  foregroundColor: kGold,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text('AUTO SS ANALYSIS 🎯 (bonus)',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'ON korle: ss nile auto cheshta korbe (na hole uporer button use koro)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                value: _floatOn,
                activeColor: kGold,
                onChanged: (_) => _toggleFloat(),
              ),
            ),
            const SizedBox(height: 8),

            InkWell(
              onTap: _keysDialog,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(_keys.isEmpty ? Icons.warning_amber_rounded : Icons.key_rounded,
                      color: _keys.isEmpty ? Colors.orange : kGold, size: 18),
                  const SizedBox(width: 8),
                  Text(_keys.isEmpty
                          ? 'Key nei — tap kore Gemini key boshao'
                          : '${_keys.length} ta key ache — tap kore edit koro',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
            const SizedBox(height: 14),

            const Text('শেষ ৫ signal:',
                style: TextStyle(color: kGold, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_history.isEmpty)
              const Text('ekhon o kono signal nei',
                  style: TextStyle(color: Colors.white24, fontSize: 11))
            else
              ..._history.map((h) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(h,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  )),
          ],
        ),
      ),
    );
  }
}

// ===== END OF FILE binary_screen.dart =====
