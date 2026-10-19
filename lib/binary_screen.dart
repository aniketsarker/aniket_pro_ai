import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BinarySignalScreen extends StatefulWidget {
  const BinarySignalScreen({super.key});

  @override
  State<BinarySignalScreen> createState() => _BinarySignalScreenState();
}

class _BinarySignalScreenState extends State<BinarySignalScreen> {
  static const MethodChannel _bin = MethodChannel('aniket_pro_ai/binary');
  static const MethodChannel _gal = MethodChannel('aniket_pro_ai/gallery');

  // Market Category Filter: ALL, OTC, LIVE, CRYPTO
  String _marketFilter = 'ALL';

  final List<String> _allPairs = [
    // Popular Pocket Option OTC Pairs
    'EUR/USD (OTC)',
    'GBP/USD (OTC)',
    'USD/JPY (OTC)',
    'AUD/USD (OTC)',
    'USD/CAD (OTC)',
    'EUR/GBP (OTC)',
    'EUR/JPY (OTC)',
    'GBP/JPY (OTC)',
    'NZD/USD (OTC)',
    'CAD/CHF (OTC)',
    'AUD/CAD (OTC)',
    'AUD/JPY (OTC)',
    'CHF/JPY (OTC)',
    'USD/CHF (OTC)',
    'EUR/AUD (OTC)',
    'EUR/CAD (OTC)',
    'GBP/AUD (OTC)',
    'GBP/CAD (OTC)',
    'USD/BDT (OTC)',
    'USD/INR (OTC)',
    'USD/PKR (OTC)',
    'USD/BRL (OTC)',
    'USD/MXN (OTC)',
    'USD/TRY (OTC)',
    'AED/CNY (OTC)',
    'GOLD (OTC)',
    'SILVER (OTC)',
    // Crypto OTC & Live (including USD/BTC & BTC/USD)
    'USD/BTC (OTC)',
    'BTC/USD (OTC)',
    'ETH/USD (OTC)',
    'USD/BTC',
    'BTC/USD',
    'ETH/USD',
    'SOL/USD',
    'BNB/USD',
    'XRP/USD',
    'ADA/USD',
    'LTC/USD',
    'TRX/USD',
    'DOT/USD',
    'BCH/USD',
    // Live Forex Pairs
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'AUD/USD',
    'USD/CAD',
    'USD/CHF',
    'EUR/GBP',
    'EUR/JPY',
    'GBP/JPY',
    'EUR/AUD',
    'EUR/CAD',
    'EUR/CHF',
    'GBP/AUD',
    'GBP/CAD',
    'GBP/CHF',
    'AUD/CAD',
    'AUD/CHF',
    'AUD/JPY',
    'AUD/NZD',
    'CAD/CHF',
    'CAD/JPY',
    'CHF/JPY',
    'NZD/USD',
    'NZD/CAD',
    'NZD/CHF',
    'NZD/JPY',
  ];

  static const List<String> _timeframes = [
    '5s',
    '15s',
    '30s',
    '1m',
    '2m',
    '3m',
    '5m',
    '15m',
  ];

  // Fast Gemini Vision Models with Automatic Fallback
  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.5-flash-lite',
    'gemini-1.5-flash',
  ];

  String _pair = 'EUR/USD (OTC)';
  String _tf = '1m';
  List<String> _keys = [];
  bool _floatOn = false;
  bool _busy = false;
  int _lastAnalyzeMs = 0;

  // Current Signal & Exact Candle Time State
  String _dir = '—';
  int _conf = 0;
  String _reason = 'Screenshot nao → Analyze Now → ss choose koro';
  String _targetTime = '—';
  String _candlePlan = '—';
  String _pattern = '—';
  String _structure = '—';
  String _smcZone = '—';
  String _entryGuide = '—';
  String _riskLevel = '—';
  bool _otcTrap = false;

  // 4-Pillar Confluence Scores (0-100)
  int _trendScore = 0;
  int _patternScore = 0;
  int _snrScore = 0;
  int _momentumScore = 0;
  int _latencyMs = 0;

  // Session Win/Loss & Money Management State
  int _wins = 0;
  int _losses = 0;
  double _baseStake = 1.0;
  final double _payoutPct = 92.0;
  String _mmMode = '1-Step MTG'; // 'Flat', '1-Step MTG', 'Compounding'
  bool _lastTradeLost = false;
  int _winStreak = 0;
  bool _showMmCalc = false;

  List<String> _hist = [];
  Timer? _timer;

  bool _isCryptoPair(String p) {
    final u = p.toUpperCase();
    return u.contains('BTC') ||
        u.contains('ETH') ||
        u.contains('SOL') ||
        u.contains('BNB') ||
        u.contains('XRP') ||
        u.contains('ADA') ||
        u.contains('LTC') ||
        u.contains('TRX') ||
        u.contains('DOT') ||
        u.contains('BCH');
  }

  List<String> _getPairsByCategory(String cat) {
    if (cat == 'OTC') {
      return _allPairs.where((p) => p.contains('(OTC)')).toList();
    } else if (cat == 'LIVE') {
      return _allPairs.where((p) => !p.contains('(OTC)') && !_isCryptoPair(p)).toList();
    } else if (cat == 'CRYPTO') {
      return _allPairs.where(_isCryptoPair).toList();
    }
    return _allPairs;
  }

  @override
  void initState() {
    super.initState();
    _bin.setMethodCallHandler(_onResult);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatHistLine(String raw) {
    final s = raw.trim();
    if (s.startsWith('UP ')) return '⬆️ ${s.substring(3)}';
    if (s.startsWith('DOWN ')) return '⬇️ ${s.substring(5)}';
    if (s.startsWith('WAIT ')) return '⏸️ ${s.substring(5)}';
    return s;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final savedPair = p.getString('bin_pair') ?? 'EUR/USD (OTC)';
    final savedTf = p.getString('bin_time') ?? '1m';
    final savedKeys = p.getStringList('bin_keys') ?? [];
    final savedHist = p.getStringList('bin_hist') ?? [];
    final savedWins = p.getInt('bin_wins') ?? 0;
    final savedLosses = p.getInt('bin_losses') ?? 0;
    final savedStake = p.getDouble('bin_stake') ?? 1.0;

    if (savedPair.isNotEmpty && !_allPairs.contains(savedPair)) {
      _allPairs.insert(0, savedPair);
    }

    bool alive = false;
    try {
      alive = (await _bin.invokeMethod<bool>('floatAlive')) ?? false;
    } catch (_) {}

    List<String> nativeHist = [];
    try {
      final raw = await _bin.invokeMethod<List>('getHist');
      if (raw != null) {
        nativeHist = raw
            .map((e) => _formatHistLine(e.toString()))
            .where((s) => s.isNotEmpty && !s.contains(' 0% '))
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _pair = savedPair.isNotEmpty ? savedPair : 'EUR/USD (OTC)';
      _tf = _timeframes.contains(savedTf) ? savedTf : '1m';
      _keys = savedKeys;
      _floatOn = alive;
      _wins = savedWins;
      _losses = savedLosses;
      _baseStake = savedStake;
      _hist = (nativeHist.isNotEmpty ? nativeHist : savedHist.map(_formatHistLine))
          .where((s) => !s.contains(' 0% '))
          .take(5)
          .toList();
    });
  }

  Future<void> _saveHist(
    String dir,
    int conf, {
    String? customPair,
    String? customTf,
    String? targetCandleTime,
    String? tag,
  }) async {
    if (conf <= 0 && dir == 'WAIT') return;
    final icon = _dirIcon(dir);
    final usePair = customPair ?? _pair;
    final useTf = customTf ?? _tf;
    final useTime = (targetCandleTime != null && targetCandleTime.isNotEmpty && targetCandleTime != '—')
        ? targetCandleTime
        : _upcomingCandleTimes.first;
    final shortTag = (tag != null && tag.isNotEmpty && tag != '—') ? ' • $tag' : '';
    final line = '$icon $conf% $usePair ($useTf) 🕒 Candle: $useTime$shortTag';

    final updated = [line, ..._hist.where((x) => x != line)].take(5).toList();
    setState(() {
      _hist = updated;
    });
    final p = await SharedPreferences.getInstance();
    await p.setStringList('bin_hist', updated);
  }

  int _periodSec() {
    switch (_tf) {
      case '5s':
        return 5;
      case '15s':
        return 15;
      case '30s':
        return 30;
      case '1m':
        return 60;
      case '2m':
        return 120;
      case '3m':
        return 180;
      case '5m':
        return 300;
      case '15m':
        return 900;
      default:
        return 60;
    }
  }

  int get _rem {
    final p = _periodSec();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return p - (nowSec % p);
  }

  String _fmtRem(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  List<String> get _upcomingCandleTimes {
    final stepSec = _periodSec();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stepMs = stepSec * 1000;
    final nextBoundaryMs = ((nowMs ~/ stepMs) + 1) * stepMs;
    final List<String> out = [];
    for (int i = 0; i < 3; i++) {
      final dt = DateTime.fromMillisecondsSinceEpoch(nextBoundaryMs + i * stepMs);
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (stepSec < 60) {
        final ss = dt.second.toString().padLeft(2, '0');
        out.add('$hh:$mm:$ss');
      } else {
        out.add('$hh:$mm');
      }
    }
    return out;
  }

  String get _entryWindowHint {
    final r = _rem;
    final p = _periodSec();
    final nextCandle = _upcomingCandleTimes.first;
    if (p >= 60) {
      if (r <= 12 || r >= p - 5) {
        return '🟢 ENTER FOR $nextCandle CANDLE';
      } else if (r <= 25) {
        return '🟡 READY FOR $nextCandle CANDLE';
      } else {
        return '⏳ NEXT CANDLE AT $nextCandle (${r}s)';
      }
    } else {
      return '⚡ NEXT SCALP CANDLE: $nextCandle';
    }
  }

  double get _recommendedStake {
    if (_mmMode == '1-Step MTG' && _lastTradeLost) {
      final mult = (100.0 + _payoutPct) / math.max(_payoutPct, 50.0);
      return double.parse((_baseStake * mult).toStringAsFixed(2));
    } else if (_mmMode == 'Compounding' && _winStreak > 0) {
      final step = math.min(_winStreak, 3);
      double amt = _baseStake;
      for (int i = 0; i < step; i++) {
        amt += amt * (_payoutPct / 100.0);
      }
      return double.parse(amt.toStringAsFixed(2));
    }
    return _baseStake;
  }

  // ── UI-Matched Searchable Market / Pair Picker Modal ──
  Future<void> _openPairSearchSheet() async {
    String query = '';
    String modalCat = _marketFilter;
    final searchCtrl = TextEditingController();

    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121422),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final baseList = _getPairsByCategory(modalCat);
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? baseList
                : _allPairs.where((p) => p.toLowerCase().contains(q)).toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.68,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '🔍 Search & Select Market Pair',
                      style: TextStyle(
                        color: Color(0xFFC6A962),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Pair nam lekho... (e.g. USD/BTC, EUR, BDT, GOLD)',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFC6A962), size: 20),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() => query = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF191C2E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFC6A962), width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFFFD54F), width: 1.5),
                        ),
                      ),
                      onChanged: (v) => setModalState(() => query = v),
                    ),
                    const SizedBox(height: 8),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in ['ALL', 'OTC', 'LIVE', 'CRYPTO'])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  c == 'OTC'
                                      ? '🔥 OTC'
                                      : c == 'LIVE'
                                          ? '🌐 Live'
                                          : c == 'CRYPTO'
                                              ? '₿ Crypto'
                                              : 'All',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: modalCat == c ? Colors.black : Colors.white70,
                                  ),
                                ),
                                selected: modalCat == c,
                                selectedColor: const Color(0xFFC6A962),
                                backgroundColor: const Color(0xFF1A1C2C),
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => setModalState(() => modalCat = c),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    if (query.trim().length >= 3 &&
                        !_allPairs.any((p) => p.toLowerCase() == query.trim().toLowerCase()))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          tileColor: const Color(0xFF232742),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFFC6A962)),
                          ),
                          leading: const Icon(Icons.add_circle, color: Color(0xFF00E676)),
                          title: Text(
                            'Use Custom Pair: "${query.trim().toUpperCase()}"',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, query.trim().toUpperCase()),
                        ),
                      ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, idx) {
                          final item = filtered[idx];
                          final isSelected = item == _pair;
                          final isOtc = item.contains('(OTC)');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 5),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF282B44) : const Color(0xFF171928),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFC6A962) : Colors.white10,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                item,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFFFFD54F) : Colors.white,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              trailing: isOtc
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B2E1E),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'OTC',
                                        style: TextStyle(
                                          color: Color(0xFFFFD54F),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'LIVE',
                                      style: TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                              onTap: () => Navigator.pop(ctx, item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (chosen != null && chosen.isNotEmpty) {
      setState(() {
        if (!_allPairs.contains(chosen)) {
          _allPairs.insert(0, chosen);
        }
        _pair = chosen;
      });
      await _syncPairTimeWithService();
    }
  }

  Future<dynamic> _onResult(MethodCall call) async {
    if (call.method == 'onBinaryResult') {
      final map = (call.arguments as Map?) ?? {};
      final dir = (map['dir'] ?? 'WAIT').toString();
      final conf = int.tryParse((map['conf'] ?? '0').toString()) ?? 0;
      final reason = (map['reason'] ?? '').toString();
      final pair = (map['pair'] ?? _pair).toString();
      final time = (map['time'] ?? _tf).toString();

      if (dir == 'STATE') {
        if (mounted) {
          setState(() {
            _floatOn = conf == 1;
          });
        }
        return null;
      }

      if (conf == 0 && (reason.contains('sob key fail') || reason.contains('parse fail'))) {
        if (!_busy && _keys.isNotEmpty) {
          await _analyzeLatestScreenshot(silentFallback: true);
          return null;
        }
      }

      _applyResult(
        dir: dir,
        conf: conf,
        reason: reason,
        pair: pair,
        time: time,
        targetTime: (map['target_time'] ?? '').toString(),
        candlePlan: (map['candle_plan'] ?? '').toString(),
        pattern: (map['pattern'] ?? _pattern).toString(),
        structure: (map['structure'] ?? _structure).toString(),
        smcZone: (map['smc'] ?? _smcZone).toString(),
        entryGuide: (map['entry'] ?? _entryGuide).toString(),
        riskLevel: (map['risk'] ?? _riskLevel).toString(),
        otcTrap: map['trap'] == true,
        trendScore: int.tryParse((map['trend_score'] ?? '0').toString()),
        patternScore: int.tryParse((map['pattern_score'] ?? '0').toString()),
        snrScore: int.tryParse((map['snr_score'] ?? '0').toString()),
        momentumScore: int.tryParse((map['momentum_score'] ?? '0').toString()),
      );
    }
    return null;
  }

  void _applyResult({
    required String dir,
    required int conf,
    required String reason,
    String? pair,
    String? time,
    String? targetTime,
    String? candlePlan,
    String? pattern,
    String? structure,
    String? smcZone,
    String? entryGuide,
    String? riskLevel,
    bool otcTrap = false,
    int? trendScore,
    int? patternScore,
    int? snrScore,
    int? momentumScore,
    int? latencyMs,
  }) {
    final cleanDir = dir.toUpperCase().trim();
    final finalDir = (cleanDir == 'UP' || cleanDir == 'CALL' || cleanDir == 'BUY')
        ? 'UP'
        : (cleanDir == 'DOWN' || cleanDir == 'PUT' || cleanDir == 'SELL')
            ? 'DOWN'
            : 'WAIT';

    final upcoming = _upcomingCandleTimes;
    final resolvedTargetTime =
        (targetTime != null && targetTime.isNotEmpty) ? targetTime : upcoming.first;
    final shortArrow = finalDir == 'UP' ? '⬆️ UP' : finalDir == 'DOWN' ? '⬇️ DOWN' : '⏸️ WAIT';
    final resolvedPlan = (candlePlan != null && candlePlan.isNotEmpty)
        ? candlePlan
        : '${upcoming[0]} $shortArrow | ${upcoming[1]} $shortArrow | ${upcoming[2]} $shortArrow';

    if (!mounted) return;
    setState(() {
      if (pair != null && pair.isNotEmpty && pair.contains('/')) {
        if (!_allPairs.contains(pair)) {
          _allPairs.insert(0, pair);
        }
        _pair = pair;
      }
      _dir = finalDir;
      _conf = conf.clamp(0, 99);
      _reason = reason.isNotEmpty ? reason : 'Analysis complete';
      _targetTime = resolvedTargetTime;
      _candlePlan = resolvedPlan;
      _pattern = (pattern != null && pattern.isNotEmpty) ? pattern : 'Price Action';
      _structure = (structure != null && structure.isNotEmpty) ? structure : 'SNR Check';
      _smcZone = (smcZone != null && smcZone.isNotEmpty) ? smcZone : 'Zone Neutral';
      _entryGuide = (entryGuide != null && entryGuide.isNotEmpty)
          ? entryGuide
          : (finalDir == 'WAIT'
              ? 'Avoid Entry • Wait for Setup'
              : 'Candle $resolvedTargetTime Open • 1-Step MTG (${upcoming[1]})');
      _riskLevel = (riskLevel != null && riskLevel.isNotEmpty)
          ? riskLevel
          : (conf >= 80 ? 'Low Risk' : conf >= 70 ? 'Medium Risk' : 'High Risk');
      _otcTrap = otcTrap;
      _trendScore = (trendScore != null && trendScore > 0)
          ? trendScore.clamp(0, 99)
          : (conf > 0 ? (conf - 3).clamp(40, 98) : 0);
      _patternScore = (patternScore != null && patternScore > 0)
          ? patternScore.clamp(0, 99)
          : (conf > 0 ? (conf + 2).clamp(40, 98) : 0);
      _snrScore = (snrScore != null && snrScore > 0)
          ? snrScore.clamp(0, 99)
          : (conf > 0 ? conf.clamp(40, 98) : 0);
      _momentumScore = (momentumScore != null && momentumScore > 0)
          ? momentumScore.clamp(0, 99)
          : (conf > 0 ? (conf - 1).clamp(40, 98) : 0);
      if (latencyMs != null) _latencyMs = latencyMs;
    });

    _saveHist(
      finalDir,
      _conf,
      customPair: _pair,
      customTf: time,
      targetCandleTime: resolvedTargetTime,
      tag: _pattern,
    );
  }

  Future<void> _pickAndAnalyze() async {
    if (_busy) return;
    if (_keys.isEmpty) {
      await _keysDialog();
      if (_keys.isEmpty) return;
    }

    try {
      final res = await _gal.invokeMethod<List>('pickFiles', {'max': 1});
      if (res == null || res.isEmpty) return;
      final path = res.first.toString();
      if (path.isEmpty) return;
      await _analyzeFilePath(path);
    } catch (e) {
      _toast('File choose error: $e');
    }
  }

  Future<void> _analyzeLatestScreenshot({bool silentFallback = false}) async {
    if (_busy) return;
    if (_keys.isEmpty) {
      if (!silentFallback) await _keysDialog();
      if (_keys.isEmpty) return;
    }

    try {
      final res = await _gal.invokeMethod<List>('listImages', {'limit': 1});
      if (res == null || res.isEmpty) {
        if (!silentFallback) _toast('Gallery-te kono screenshot pawa jayni');
        return;
      }
      final first = res.first;
      if (first is Map) {
        final path = (first['path'] ?? '').toString();
        if (path.isNotEmpty) {
          await _analyzeFilePath(path, fromAuto: silentFallback);
        }
      }
    } catch (e) {
      if (!silentFallback) _toast('Latest SS load error: $e');
    }
  }

  Future<void> _analyzeFilePath(String path, {bool fromAuto = false}) async {
    if (_busy) return;
    final file = File(path);
    if (!await file.exists()) {
      if (!fromAuto) _toast('Screenshot file pawa jayni');
      return;
    }

    final startMs = DateTime.now().millisecondsSinceEpoch;
    _lastAnalyzeMs = startMs;

    setState(() {
      _busy = true;
      _reason = '⚡ Fast AI Pro Price Action + Candle Time Schedule analyze korche...';
    });

    try {
      final rawBytes = await file.readAsBytes();
      Uint8List sendBytes = rawBytes;

      try {
        final comp = await _gal.invokeMethod<Uint8List>('compress', {
          'bytes': rawBytes,
          'maxKB': 180,
        });
        if (comp != null && comp.isNotEmpty) {
          sendBytes = comp;
        }
      } catch (_) {}

      final b64 = base64Encode(sendBytes);
      final parsed = await _geminiVision(b64);
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;

      final dir = (parsed['dir'] ?? 'WAIT').toString();
      final conf = int.tryParse((parsed['conf'] ?? '0').toString()) ?? 0;
      final reason = (parsed['reason'] ?? 'Analysis complete').toString();
      final detPair = (parsed['detected_pair'] ?? '').toString().trim();

      _applyResult(
        dir: dir,
        conf: conf,
        reason: reason,
        pair: (detPair.isNotEmpty && detPair != 'UNKNOWN' && detPair.contains('/')) ? detPair : _pair,
        targetTime: (parsed['target_time'] ?? '').toString(),
        candlePlan: (parsed['candle_plan'] ?? '').toString(),
        pattern: (parsed['pattern'] ?? 'Price Action').toString(),
        structure: (parsed['structure'] ?? 'SNR Level').toString(),
        smcZone: (parsed['smc'] ?? 'Order Block / FVG').toString(),
        entryGuide: (parsed['entry'] ?? '').toString(),
        riskLevel: (parsed['risk'] ?? 'Normal').toString(),
        otcTrap: parsed['trap'] == true,
        trendScore: int.tryParse((parsed['trend_score'] ?? '0').toString()),
        patternScore: int.tryParse((parsed['pattern_score'] ?? '0').toString()),
        snrScore: int.tryParse((parsed['snr_score'] ?? '0').toString()),
        momentumScore: int.tryParse((parsed['momentum_score'] ?? '0').toString()),
        latencyMs: elapsed,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _dir = 'WAIT';
          _conf = 0;
          _reason = 'Analysis error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _geminiVision(String b64) async {
    final now = DateTime.now();
    final nowStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final times = _upcomingCandleTimes;
    final t1 = times[0];
    final t2 = times[1];
    final t3 = times[2];

    final isOtc = _pair.contains('(OTC)');
    final marketType = isOtc ? 'Pocket Option OTC algorithmic market' : 'Live Interbank market';
    final prompt = 'You are an elite institutional Binary Options & Pocket Option Price Action Master Trader.\n'
        'Current time is $nowStr. Selected pair is $_pair on $_tf timeframe ($marketType).\n'
        'The upcoming 3 candle open times are: Candle 1 = $t1, Candle 2 = $t2, Candle 3 = $t3.\n'
        'If a different pair name (e.g. USD/BTC (OTC), EUR/JPY (OTC)) is clearly visible on the screenshot, put it in "detected_pair", otherwise use "$_pair".\n\n'
        'Perform a complete 6-Pillar Binary Trading Course Analysis:\n'
        '1. CANDLESTICK PSYCHOLOGY & PATTERNS: Hammer, Shooting Star, Bullish/Bearish Engulfing, Morning/Evening Star, Tweezer Top/Bottom, Three Soldiers/Crows, Marubozu, Doji, Upper/Lower Wick Rejection, Exhaustion.\n'
        '2. MARKET STRUCTURE & TREND: Uptrend (HH/HL), Downtrend (LH/LL), Ranging, BOS, CHoCH.\n'
        '3. SUPPORT & RESISTANCE (SNR) + SMART MONEY CONCEPTS (SMC): Horizontal SNR, Flip Zones (SBR/RBS), Round Numbers, Order Blocks (OB), Fair Value Gaps (FVG), Liquidity Sweeps.\n'
        '4. CLASSIC CHART PATTERNS: Double Top (M), Double Bottom (W), Head & Shoulders, Triangle, Wedge, Flag.\n'
        '5. INDICATOR CONFLUENCE: RSI, Bollinger Bands, Stochastic, MACD, EMA.\n'
        '6. POCKET OPTION OTC TRAP FILTER & EXACT CANDLE TIMING: Predict the exact direction (UP or DOWN) for each upcoming candle ($t1, $t2, and $t3), and specify which exact candle time ($t1, $t2, or $t3) is the primary target candle in "target_time".\n\n'
        'Reply ONLY with a valid JSON object matching this exact schema:\n'
        '{\n'
        '  "dir": "UP" or "DOWN" or "WAIT",\n'
        '  "conf": 85,\n'
        '  "detected_pair": "$_pair",\n'
        '  "target_time": "$t1",\n'
        '  "candle_plan": "$t1 ⬆️ UP | $t2 ⬆️ UP | $t3 ⬆️ UP",\n'
        '  "pattern": "Short candle pattern name (e.g. Bullish Engulfing + Wick Rejection)",\n'
        '  "structure": "Trend & SNR summary (e.g. Uptrend HH/HL • Support Bounce)",\n'
        '  "smc": "SMC / Indicator confluence (e.g. Bullish OB + FVG Fill)",\n'
        '  "entry": "$t1 Candle Open • 1-Step MTG ($t2)",\n'
        '  "risk": "Low Risk" or "Medium Risk" or "High Risk - Avoid",\n'
        '  "trap": false,\n'
        '  "trend_score": 86,\n'
        '  "pattern_score": 88,\n'
        '  "snr_score": 84,\n'
        '  "momentum_score": 80,\n'
        '  "reason": "Concise Banglish explanation mentioning exact candle time ($t1 / $t2 / $t3) and why it will go UP or DOWN"\n'
        '}';

    String lastError = 'sob key fail — net/key check koro';

    for (final rawKey in _keys) {
      final key = rawKey.trim();
      if (key.isEmpty) continue;

      for (final model in _models) {
        HttpClient? client;
        try {
          client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
          final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
          );
          final req = await client.postUrl(uri).timeout(const Duration(seconds: 10));
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

          final bodyMap = {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': b64,
                    }
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.15,
              'maxOutputTokens': 550,
              'responseMimeType': 'application/json',
            }
          };

          req.add(utf8.encode(jsonEncode(bodyMap)));
          final resp = await req.close().timeout(const Duration(seconds: 16));
          final respText = await resp.transform(utf8.decoder).join();

          if (resp.statusCode != 200) {
            lastError = 'HTTP ${resp.statusCode} ($model)';
            continue;
          }

          final root = jsonDecode(respText) as Map<String, dynamic>;
          final candidates = root['candidates'] as List?;
          if (candidates == null || candidates.isEmpty) {
            lastError = 'Empty AI response ($model)';
            continue;
          }

          final content = (candidates.first as Map)['content'] as Map?;
          final parts = content?['parts'] as List?;
          if (parts == null || parts.isEmpty) continue;

          final buffer = StringBuffer();
          for (final p in parts) {
            if (p is Map && p['text'] != null) {
              buffer.write(p['text'].toString());
            }
          }

          final rawOut = buffer.toString().trim();
          final parsed = _extractJsonMap(rawOut);
          if (parsed != null) {
            return parsed;
          } else {
            lastError = 'JSON parse error ($model)';
          }
        } catch (_) {
          lastError = 'Net/Timeout error';
        } finally {
          client?.close(force: true);
        }
      }
    }

    return {
      'dir': 'WAIT',
      'conf': 0,
      'target_time': t1,
      'candle_plan': '$t1 ⏸️ WAIT',
      'pattern': 'API / Key Check',
      'structure': 'No Signal',
      'smc': 'Check Internet / Gemini API Key',
      'entry': 'Tap Key Box below to verify API key',
      'risk': 'No Trade',
      'trap': false,
      'reason': lastError,
    };
  }

  Map<String, dynamic>? _extractJsonMap(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end > start) {
        final jsonSlice = raw.substring(start, end + 1);
        final decoded = jsonDecode(jsonSlice);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      final dirMatch = RegExp(
        r'"dir"\s*:\s*"(UP|DOWN|WAIT|CALL|PUT)"',
        caseSensitive: false,
      ).firstMatch(raw);
      final confMatch = RegExp(r'"conf"\s*:\s*(\d+)').firstMatch(raw);
      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]+)"').firstMatch(raw);
      final patMatch = RegExp(r'"pattern"\s*:\s*"([^"]+)"').firstMatch(raw);
      if (dirMatch != null) {
        return {
          'dir': dirMatch.group(1)!.toUpperCase(),
          'conf': int.tryParse(confMatch?.group(1) ?? '70') ?? 70,
          'pattern': patMatch?.group(1) ?? 'Price Action Setup',
          'reason': reasonMatch?.group(1) ?? 'Price action confluence detected',
        };
      }
    }
    return null;
  }

  Future<void> _toggleFloat(bool val) async {
    if (val) {
      if (_keys.isEmpty) {
        await _keysDialog();
        if (_keys.isEmpty) return;
      }
      try {
        final can = (await _gal.invokeMethod<bool>('canOverlay')) ?? false;
        if (!can) {
          await _gal.invokeMethod('openOverlaySettings');
          return;
        }
        await _bin.invokeMethod('startFloat', {
          'keys': _keys,
          'pair': _pair,
          'time': _tf,
        });
        setState(() => _floatOn = true);
      } catch (e) {
        _toast('Auto SS start error: $e');
      }
    } else {
      try {
        await _bin.invokeMethod('stopFloat');
      } catch (_) {}
      setState(() => _floatOn = false);
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('bin_float', _floatOn);
  }

  Future<void> _syncPairTimeWithService() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bin_pair', _pair);
    await p.setString('bin_time', _tf);
    if (_floatOn) {
      try {
        await _bin.invokeMethod('startFloat', {
          'keys': _keys,
          'pair': _pair,
          'time': _tf,
        });
      } catch (_) {}
    }
  }

  Future<void> _recordOutcome(bool isWin) async {
    setState(() {
      if (isWin) {
        _wins++;
        _lastTradeLost = false;
        _winStreak++;
      } else {
        _losses++;
        _lastTradeLost = true;
        _winStreak = 0;
      }
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt('bin_wins', _wins);
    await p.setInt('bin_losses', _losses);
  }

  Future<void> _resetStats() async {
    setState(() {
      _wins = 0;
      _losses = 0;
      _lastTradeLost = false;
      _winStreak = 0;
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt('bin_wins', 0);
    await p.setInt('bin_losses', 0);
  }

  Future<void> _keysDialog() async {
    final ctrl = TextEditingController(text: _keys.join('\n'));
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161826),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '🔑 Gemini API Keys (1 per line)',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Multiple key dile 1ta busy hole auto porer key diye fast kaj korbe (gemini-2.5-flash + fallback):',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'AIzaSy...\nAIzaSy...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0E101A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF3E4259)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC6A962),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final list = ctrl.text
                  .split(RegExp(r'[\r\n,]+'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(ctx, list);
            },
            child: const Text('Save Keys', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved != null) {
      setState(() => _keys = saved);
      final p = await SharedPreferences.getInstance();
      await p.setStringList('bin_keys', saved);
      if (_floatOn) {
        await _syncPairTimeWithService();
      }
    }
  }

  void _toast(String msg) {
    try {
      _gal.invokeMethod('toast', {'text': msg});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Color _dirColor(String d) {
    if (d == 'UP') return const Color(0xFF00E676);
    if (d == 'DOWN') return const Color(0xFFFF5252);
    return const Color(0xFFFFB300);
  }

  String _dirIcon(String d) {
    if (d == 'UP') return '⬆️';
    if (d == 'DOWN') return '⬇️';
    return '⏸️';
  }

  String _dirLabel(String d) {
    if (d == 'UP') return 'CALL / UP';
    if (d == 'DOWN') return 'PUT / DOWN';
    if (d == '—') return '— —';
    return 'WAIT';
  }

  @override
  Widget build(BuildContext context) {
    final sigColor = _dirColor(_dir);
    final totalTrades = _wins + _losses;
    final winRate = totalTrades > 0 ? ((_wins * 100) / totalTrades).round() : 0;
    final nextTimes = _upcomingCandleTimes;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Quick Market Filter Chips (ALL / OTC / LIVE / CRYPTO)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in ['ALL', 'OTC', 'LIVE', 'CRYPTO'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            f == 'OTC'
                                ? '🔥 OTC Pairs'
                                : f == 'LIVE'
                                    ? '🌐 Live Forex'
                                    : f == 'CRYPTO'
                                        ? '₿ Crypto'
                                        : 'All (${_allPairs.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _marketFilter == f ? Colors.black : Colors.white70,
                            ),
                          ),
                          selected: _marketFilter == f,
                          selectedColor: const Color(0xFFC6A962),
                          backgroundColor: const Color(0xFF171824),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() {
                              _marketFilter = f;
                              final catList = _getPairsByCategory(f);
                              if (catList.isNotEmpty && !catList.contains(_pair)) {
                                _pair = catList.first;
                              }
                            });
                            _syncPairTimeWithService();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 2. Searchable Market Pair Box + Timeframe Selector Row
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: InkWell(
                      onTap: _openPairSearchSheet,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151624),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFC6A962), width: 0.9),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Color(0xFFC6A962), size: 19),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pair,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF23263A),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'Search',
                                style: TextStyle(
                                  color: Color(0xFFFFD54F),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151624),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E324B)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _tf,
                          dropdownColor: const Color(0xFF191B2C),
                          isExpanded: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          items: _timeframes
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _tf = v);
                            _syncPairTimeWithService();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 3. Main Pro Signal Card (with Exact Target Candle Time & Multi-Candle Schedule)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF17192D), Color(0xFF111322)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _dir == '—' ? const Color(0xFF393E5E) : sigColor.withOpacity(0.75),
                    width: 1.4,
                  ),
                  boxShadow: [
                    if (_dir != '—')
                      BoxShadow(
                        color: sigColor.withOpacity(0.14),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _entryWindowHint,
                          style: const TextStyle(
                            color: Color(0xFFC6A962),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_latencyMs > 0)
                          Text(
                            '⚡ ${(_latencyMs / 1000).toStringAsFixed(1)}s AI',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _dir == '—' ? '—  —' : '${_dirIcon(_dir)} ${_dirLabel(_dir)}',
                            style: TextStyle(
                              color: _dir == '—' ? Colors.white54 : sigColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Text(
                            '  |  ',
                            style: TextStyle(color: Colors.white24, fontSize: 20),
                          ),
                          Text(
                            '$_conf%',
                            style: TextStyle(
                              color: _conf >= 75 ? const Color(0xFF00E676) : Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            '  |  ',
                            style: TextStyle(color: Colors.white24, fontSize: 20),
                          ),
                          Text(
                            '${_fmtRem(_rem)} baki',
                            style: const TextStyle(
                              color: Color(0xFFFFD54F),
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E101D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2D3250)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _dir == '—'
                                ? '🕒 Upcoming Candles: ${nextTimes[0]} • ${nextTimes[1]} • ${nextTimes[2]}'
                                : '🎯 Target Candle Time: $_targetTime (${_dirLabel(_dir)})',
                            style: TextStyle(
                              color: _dir == '—' ? const Color(0xFFFFD54F) : sigColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_candlePlan != '—') ...[
                            const SizedBox(height: 3),
                            Text(
                              '🕯️ Schedule: $_candlePlan',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      '$_pair • $_tf  |  Next Stake: \$${_recommendedStake.toStringAsFixed(2)} ($_mmMode)',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),

                    if (_otcTrap) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A151B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: const Text(
                          '⚠️ OTC Manipulation / Choppy Trap Detected — Trade Skip Koro!',
                          style: TextStyle(
                            color: Color(0xFFFF8A80),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Text(
                      _reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),

                    if (_conf > 0 || _dir != '—') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          _infoBadge('🕯️ Pattern', _pattern, const Color(0xFF263238)),
                          _infoBadge('📐 Structure', _structure, const Color(0xFF1E2746)),
                          _infoBadge('🏦 SMC / Zone', _smcZone, const Color(0xFF2B2240)),
                          _infoBadge('🎯 Entry', _entryGuide, const Color(0xFF1B352E)),
                          _infoBadge('🛡️ Risk', _riskLevel, const Color(0xFF3A2A1D)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _scoreMiniBar('Trend', _trendScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('Pattern', _patternScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('SNR/SMC', _snrScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('Momentum', _momentumScore),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. Primary Action Buttons: File Picker + 1-Tap Latest Screenshot
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4B4637),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFFC6A962), width: 0.9),
                          ),
                        ),
                        onPressed: _busy ? null : _pickAndAnalyze,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.folder_open, color: Color(0xFFFFD54F), size: 20),
                        label: Text(
                          _busy ? 'Analyzing Chart...' : 'Analyze Now — ss choose koro',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E243B),
                          foregroundColor: const Color(0xFF00E676),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF00E676), width: 0.8),
                          ),
                        ),
                        onPressed: _busy ? null : () => _analyzeLatestScreenshot(silentFallback: false),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt, size: 18, color: Color(0xFF00E676)),
                            Text(
                              'Latest SS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 5. AUTO SS ANALYSIS Toggle Card (Smart In-Bubble UP/DOWN + Candle Time HUD)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF15172B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF282D4F)),
                ),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.stars_rounded,
                          color: Color(0xFFC6A962),
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SMART BUBBLE SIGNAL 🎯 (In-Bubble UP/DOWN)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _floatOn
                                ? '🟢 ACTIVE: অ্যাপে ঢোকা লাগবে না—Pocket Option-এ SS নিলে বাবলের ভেতরেই UP/DOWN ও ক্যান্ডেলের টাইম (যেমন ${nextTimes[0]}, ${nextTimes[1]}) দেখাবে!'
                                : 'ON korle: App Logo Bubble ভাসবে এবং বাবলের ভেতরেই UP/DOWN ও ক্যান্ডেলের সঠিক টাইম বলে দেবে',
                            style: const TextStyle(color: Colors.white60, fontSize: 11.2),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _floatOn,
                      activeColor: const Color(0xFFC6A962),
                      onChanged: _toggleFloat,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 6. Session Win/Loss & Money Management Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF141624),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF262A40)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📊 Win Rate: $winRate% (${_wins}W / ${_losses}L)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: () => _recordOutcome(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF113826),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '✅ WIN',
                                  style: TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _recordOutcome(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3E161B),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '❌ LOSS',
                                  style: TextStyle(
                                    color: Color(0xFFFF5252),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _showMmCalc = !_showMmCalc),
                              child: Icon(
                                _showMmCalc ? Icons.expand_less : Icons.calculate_outlined,
                                color: const Color(0xFFC6A962),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_showMmCalc) ...[
                      const Divider(color: Colors.white12, height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final m in ['Flat', '1-Step MTG', 'Compounding'])
                            ChoiceChip(
                              label: Text(m, style: const TextStyle(fontSize: 11)),
                              selected: _mmMode == m,
                              selectedColor: const Color(0xFFC6A962),
                              onSelected: (_) => setState(() => _mmMode = m),
                            ),
                          TextButton(
                            onPressed: _resetStats,
                            child: const Text(
                              'Reset W/L',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 7. API Key Management Bar
              InkWell(
                onTap: _keysDialog,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15172B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF282D4F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key, color: Color(0xFFC6A962), size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _keys.isEmpty
                              ? 'Key nei — tap kore Gemini key boshao'
                              : '${_keys.length} ta key ache — tap kore edit koro',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        ),
                      ),
                      const Icon(Icons.edit, color: Colors.white38, size: 15),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 8. Last 5 Signals History
              const Text(
                'শেষ ৫ signal:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              if (_hist.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181920),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ekhon o kono signal nei',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              else
                ..._hist.map(
                  (h) => Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1C22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      h,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(String label, String val, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '$label: $val',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _scoreMiniBar(String title, int score) {
    final c = score >= 75
        ? const Color(0xFF00E676)
        : score >= 60
            ? const Color(0xFFFFD54F)
            : const Color(0xFFFF5252);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white60, fontSize: 9.5)),
              Text(
                '$score%',
                style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (score.clamp(0, 100)) / 100.0,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(c),
            ),
          ),
        ],
      ),
    );
  }
}
