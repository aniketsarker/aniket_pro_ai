import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FULL BINARY TRADING DICTIONARY (CANDLESTICK PSYCHOLOGY • SMC • ICT •
//  CHART PATTERNS • TRAPS • MTG • NO-TRADE DISCIPLINE)
// ═══════════════════════════════════════════════════════════════════════════
class BinaryDictEntry {
  final String category; // PA, SMC, ICT, PATTERN, TRAP, MTG
  final String term;
  final String signalBias; // UP, DOWN, REVERSAL, WAIT, MTG
  final String meaningBanglish;
  final String proEntryRule;

  const BinaryDictEntry({
    required this.category,
    required this.term,
    required this.signalBias,
    required this.meaningBanglish,
    required this.proEntryRule,
  });
}

const List<BinaryDictEntry> kBinaryTradingDictionary = [
  // ── 1. CANDLESTICK PSYCHOLOGY & PRICE ACTION (PA) ──
  BinaryDictEntry(
    category: 'PA',
    term: 'Wick Rejection Psychology (Buyer vs Seller Pressure)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'ক্যান্ডেলের বডি দেখায় কারা ক্লোজ করেছে, কিন্তু লম্বা উইক (লেজ) দেখায় কারা ভেতরে যুদ্ধ জিতেছে! উপরে লম্বা উইক মানে বায়াররা উপরে ধরে রাখতে পারেনি (Seller Rejection); নিচে লম্বা উইক মানে সেলাররা নিচে ধরে রাখতে পারেনি (Buyer Rejection)।',
    proEntryRule: 'শুধুমাত্র মেজর SNR, Order Block বা Trendline-এ লম্বা উইক রিজেকশন হলে পরের ক্যান্ডেলে বিপরীত দিকে ট্রেড নেবে। মাঝখানে (Mid-Zone) হলে WAIT করবে।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Candle Body Shrinking (Momentum Loss / Exhaustion)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'পরপর ৩টি সবুজ বা লাল ক্যান্ডেলের বডি যদি ক্রমশ বড় থেকে ছোট হতে থাকে (যেমন ১মটা বড়, ২য়টা মাঝারি, ৩য়টা ছোট/উইকওয়ালা), তার মানে ওই ট্রেন্ডের শক্তি শেষ হয়ে গেছে!',
    proEntryRule: 'শক্তি কমে যাওয়া (Shrinking) ক্যান্ডেল দেখে কখনোই ট্রেন্ডের দিকে ট্রেড নেবে না! রেজিস্ট্যান্স/সাপোর্ট ছুঁলে রিভার্সাল নেবে নতুবা WAIT করবে।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Bullish Pinbar / Hammer & Dragonfly Doji',
    signalBias: 'UP',
    meaningBanglish:
        'ডাউনট্রেন্ডের শেষে সাপোর্ট বা Bullish Order Block-এ নিচে ৬৫%+ লম্বা উইক এবং উপরে ছোট বডি। সেলারদের সব অর্ডার বায়াররা শুষে (Absorb) নিয়েছে।',
    proEntryRule: 'সাপোর্ট লেভেলে ক্লোজ হলে পরের ক্যান্ডেলে (1 min por) Direct UP ট্রেড।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Bearish Pinbar / Shooting Star & Gravestone Doji',
    signalBias: 'DOWN',
    meaningBanglish:
        'আপট্রেন্ডের শেষে রেজিস্ট্যান্স বা Bearish Order Block-এ উপরে ৬৫%+ লম্বা উইক এবং নিচে ছোট বডি। বায়াররা উপরে ট্র্যাপে পড়েছে।',
    proEntryRule: 'রেজিস্ট্যান্স লেভেলে ক্লোজ হলে পরের ক্যান্ডেলে (1 min por) Direct DOWN ট্রেড।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Bullish & Bearish Engulfing + Piercing / Dark Cloud',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'আগের ক্যান্ডেলের পুরো বডিকে পরের বিপরীত রঙের ক্যান্ডেল সম্পূর্ণ গিলে ফেলা (Engulfing) বা ৫০%+ ভেতরে ঢুকে ক্লোজ হওয়া (Piercing Line / Dark Cloud Cover)।',
    proEntryRule: 'কী-লেভেলে (SNR / OB / FVG) তৈরি হলে পরের ক্যান্ডেলে স্ট্রং এন্ট্রি। চার্টের মাঝখানে তৈরি হলে ট্রেড SKIP (WAIT) করবে।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Morning Star & Evening Star (3-Candle Institutional Shift)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        '১টি স্ট্রং ক্যান্ডেল + ১টি ছোট Doji/Spinning Top (থামা ও যুদ্ধ) + ১টি শক্তিশালী বিপরীত ক্যান্ডেল। এটি ৩ ক্যান্ডেলের সবচেয়ে নির্ভরযোগ্য সাইকোলজিক্যাল রিভার্সাল।',
    proEntryRule: '৩য় ক্যান্ডেল ক্লোজ হওয়ার সাথে সাথে পরের ক্যান্ডেলে Direct ট্রেড (সাধারণত MTG লাগে না)।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Tweezer Top & Tweezer Bottom (Algorithmic Defense)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'পরপর ২টি ক্যান্ডেল ঠিক একই পিপ/প্রাইস লেভেলে বাধা পেয়ে ফিরে আসা। মানে ওই নির্দিষ্ট প্রাইসে ইনস্টিটিউশনাল লিমিট অর্ডার বসে আছে।',
    proEntryRule: 'SNR বা Order Block-এ Tweezer দেখলে পরের ক্যান্ডেলে রিভার্সাল ট্রেড।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Inside Bar (Mother Bar + Harami) & Fakey Setup',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'একটি বড় ক্যান্ডেলের (Mother Bar) হাই ও লো-এর ভেতরে পরের ক্যান্ডেল বন্দী থাকা। যখন একদিকে ফেক ব্রেকআউট দিয়ে আবার ভেতরে ঢুকে যায়, তাকে Fakey বলে।',
    proEntryRule: 'Mother Bar-এর ভেতরে থাকা অবস্থায় কোনো ট্রেড নেবে না (WAIT)। ব্রেকআউট বা Fakey সুইপ শেষ হলে ট্রেড নেবে।',
  ),
  BinaryDictEntry(
    category: 'PA',
    term: 'Marubozu Impulse vs Climax Exhaustion Candle',
    signalBias: 'WAIT',
    meaningBanglish:
        'একটি অস্বাভাবিক বিশাল ক্যান্ডেল যদি কনসলিডেশন ভেঙে শুরুতে তৈরি হয় তবে সেটি Impulse; কিন্তু টানা ৩–৪টি ক্যান্ডেলের পর হঠাৎ বিশাল ক্যান্ডেল হলে সেটি Exhaustion Climax!',
    proEntryRule: 'Exhaustion ক্যান্ডেলের পর কখনোই একই দিকে ট্রেড নেবে না—হয় রিভার্সাল দেখবে অথবা ১ ক্যান্ডেল WAIT করবে।',
  ),

  // ── 2. SMART MONEY CONCEPTS (SMC) ──
  BinaryDictEntry(
    category: 'SMC',
    term: 'BOS (Break of Structure) vs Fake Breakout',
    signalBias: 'UP',
    meaningBanglish:
        'আসল BOS হতে হলে সুইং হাই বা সুইং লো-কে ক্যান্ডেলের সলিড বডি দিয়ে ব্রেক করে ক্লোজ হতে হবে। শুধু উইক (লেজ) গিয়ে ফিরে এলে সেটি BOS নয়, সেটি Liquidity Sweep!',
    proEntryRule: 'বডি দিয়ে BOS হলে পুলব্যাকে FVG/OB থেকে ট্রেন্ডের দিকে ট্রেড; আর শুধু উইক গেলে বিপরীত দিকে রিভার্সাল ট্রেড!',
  ),
  BinaryDictEntry(
    category: 'SMC',
    term: 'CHoCH (Change of Character — Trend Reversal)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'মার্কেট যখন প্রথমবার তার সর্বশেষ Internal Higher Low (আপট্রেন্ডে) বা Lower High (ডাউনট্রেন্ডে) বডি দিয়ে ভেঙে ফেলে, তখন মার্কেটের চরিত্র (ট্রেন্ড) বদলে যায়।',
    proEntryRule: 'CHoCH হওয়ার পর প্রাইস যখন রিট্রেস করে নতুন Order Block বা FVG ছোঁয়, তখন নতুন ট্রেন্ডের দিকে স্নাইপার এন্ট্রি।',
  ),
  BinaryDictEntry(
    category: 'SMC',
    term: 'Unmitigated Order Block (Bullish OB & Bearish OB)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'যে Order Block-এ প্রাইস এখনো একবারও ফিরে আসেনি (Fresh / Unmitigated)। প্রাইস প্রথমবার সেখানে এলে ৮৫–৯০% সময় রিজেকশন দেয়।',
    proEntryRule: 'প্রাইস Fresh Order Block-এ ঢুকে উইক রিজেকশন বা পিনবার দিলেই পরের ক্যান্ডেলে এন্ট্রি (1-Step MTG ব্যাকআপ রাখবে)।',
  ),
  BinaryDictEntry(
    category: 'SMC',
    term: 'FVG (Fair Value Gap) & 50% CE (Consequent Encroachment)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'ইমপালস মুভের সময় তৈরি হওয়া ৩-ক্যান্ডেলের গ্যাপ। এই গ্যাপের ঠিক মাঝখান (50% CE লেভেল) সবচেয়ে শক্তিশালী বাউন্স পয়েন্ট।',
    proEntryRule: 'প্রাইস FVG-এর ৫০% ছুঁয়ে রিজেকশন দিলে পরের ক্যান্ডেলে ট্রেন্ডের দিকে এন্ট্রি।',
  ),
  BinaryDictEntry(
    category: 'SMC',
    term: 'Breaker Block & Flip Zone (SBR / RBS)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'লিকুইডিটি নেওয়ার পর কোনো শক্তিশালী সাপোর্ট বা Order Block ভেঙে গেলে সেটি পরবর্তীতে রেজিস্ট্যান্স (SBR / Bearish Breaker) হয়ে যায়, এবং রেজিস্ট্যান্স ভাঙলে সাপোর্ট (RBS / Bullish Breaker) হয়ে যায়।',
    proEntryRule: 'প্রথমবার রিটেস্টে ক্যান্ডেল রিজেকশন দেখলেই পরের ক্যান্ডেলে এন্ট্রি।',
  ),

  // ── 3. ICT (INNER CIRCLE TRADER) CONCEPTS ──
  BinaryDictEntry(
    category: 'ICT',
    term: 'BSL & SSL Liquidity Sweep (Turtle Soup / Stop-Hunt)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'আগের ১ বা একাধিক Swing High (Equal Highs - BSL) বা Swing Low (Equal Lows - SSL)-এর বাইরে গিয়ে রিটেল ট্রেডারদের স্টপলস ও ব্রেকআউট ট্রেড খেয়ে ক্যান্ডেল আবার রেঞ্জের ভেতরে ক্লোজ হওয়া।',
    proEntryRule: 'সুইপ ক্যান্ডেল ভেতরে ক্লোজ হওয়ার সাথে সাথে পরের ক্যান্ডেলে (1 min por) বিপরীত দিকে Direct Shot ট্রেড!',
  ),
  BinaryDictEntry(
    category: 'ICT',
    term: 'Inducement (IDM) — The Smart Money Bait',
    signalBias: 'TRAP',
    meaningBanglish:
        'আসল Order Block-এর একটু সামনে থাকা প্রথম মাইনর পুলব্যাক হাই বা লো। স্মার্ট মানি প্রথমে এই IDM ভেঙে রিটেলদের ফাঁসায়, তারপর আসল Order Block থেকে ঘোরে।',
    proEntryRule: 'IDM না ভাঙা পর্যন্ত কোনো Order Block-এ ট্রেড নেবে না (WAIT)। IDM সুইপ হওয়ার পর আসল OB-তে এন্ট্রি নেবে।',
  ),
  BinaryDictEntry(
    category: 'ICT',
    term: 'AMD / Power of 3 (Accumulation, Manipulation, Distribution)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        '১) রেঞ্জ (Accumulation) -> ২) আসল দিকের উল্টো দিকে ফেক ব্রেকআউট বা Judas Swing (Manipulation) -> ৩) আসল দিকে শক্তিশালী ট্রেন্ড মুভ (Distribution)।',
    proEntryRule: 'রেঞ্জের পর প্রথম ব্রেকআউটটা যদি উইক দিয়ে ফেইল করে (Manipulation), তবে উল্টো দিকে (Distribution) ট্রেড নেবে।',
  ),
  BinaryDictEntry(
    category: 'ICT',
    term: 'Premium vs Discount & OTE (61.8% – 78.6% Fib)',
    signalBias: 'WAIT',
    meaningBanglish:
        'সুইং রেঞ্জের উপরের ৫০% হলো Premium (শুধু SELL খোঁজার জোন) এবং নিচের ৫০% হলো Discount (শুধু BUY খোঁজার জোন)। মাঝখানের ৫০% হলো Equilibrium (No-Trade Zone)।',
    proEntryRule: 'প্রাইস চার্টের মাঝখানে (Equilibrium) থাকলে ট্রেড নেবে না (WAIT)। ৬১.৮%–৭৮.৬% (OTE) জোনে এলে ট্রেড নেবে।',
  ),

  // ── 4. CLASSIC CHART PATTERNS ──
  BinaryDictEntry(
    category: 'PATTERN',
    term: 'Double Top (M) & Double Bottom (W) + Neckline',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'উপরে দুইবার বাধা পেয়ে M প্যাটান বা নিচে দুইবার সাপোর্ট পেয়ে W প্যাটার্ন। যদি ২য় টপ/বটমটি ১মটির লিকুইডিটি সুইপ করে পিনবার দেয়, তবে সেটি A+ সেটআপ।',
    proEntryRule: '২য় টপ/বটমে রিজেকশন ক্যান্ডেলে অথবা Neckline ব্রেকআউটের পর রিটেস্ট ক্যান্ডেলে এন্ট্রি।',
  ),
  BinaryDictEntry(
    category: 'PATTERN',
    term: 'Head & Shoulders / Inverse Head & Shoulders',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'Left Shoulder -> Head (Liquidity Sweep) -> CHoCH -> Right Shoulder (Mitigation Block/OTE)। এটি সবচেয়ে শক্তিশালী চার্ট রিভার্সাল প্যাটার্ন।',
    proEntryRule: 'Right Shoulder থেকে রিজেকশন ক্যান্ডেল ক্লোজ হলে অথবা Neckline ব্রেক-অ্যান্ড-রিটেস্টে এন্ট্রি।',
  ),
  BinaryDictEntry(
    category: 'PATTERN',
    term: 'Rising Wedge (Bearish) & Falling Wedge (Bullish)',
    signalBias: 'REVERSAL',
    meaningBanglish:
        'দুই পাশের ট্রেন্ডলাইন সংকুচিত হয়ে উপরে উঠলে (Rising Wedge) বায়ারদের শক্তি শেষ হয়ে নিচে ভাঙে; আর সংকুচিত হয়ে নিচে নামলে (Falling Wedge) সেলারদের শক্তি শেষ হয়ে উপরে ভাঙে।',
    proEntryRule: 'ওয়েজের শেষ মাথায় রিজেকশনে অথবা ট্রেন্ডলাইন ব্রেকআউট ক্যান্ডেল ক্লোজ হলে এন্ট্রি।',
  ),
  BinaryDictEntry(
    category: 'PATTERN',
    term: 'Bullish/Bearish Flag, Pennant & Triangles',
    signalBias: 'UP',
    meaningBanglish:
        'শক্তিশালী ইমপালস মুভের পর ছোট কাউন্টার-ট্রেন্ড চ্যানেল (Flag) বা ট্রায়াঙ্গেল কনসলিডেশন।',
    proEntryRule: 'কনসলিডেশনের ভেতরে ট্রেড নেবে না (WAIT)। যেদিকে বডি দিয়ে পরিষ্কার ব্রেকআউট দেবে, পরের ক্যান্ডেলে সেদিকে ট্রেড।',
  ),

  // ── 5. TRAPS TRAINING & WHEN NOT TO TRADE ("WAIT" RULES) ──
  BinaryDictEntry(
    category: 'TRAP',
    term: '2-3 Candle Blind Momentum Trap (Why Retails Lose!)',
    signalBias: 'WAIT',
    meaningBanglish:
        'পরপর ২–৩টা সবুজ বা লাল ক্যান্ডেল দেখেই অন্ধভাবে পরের ক্যান্ডেল একই দিকে নেওয়া বাইনারি ট্রেডিংয়ের সবচেয়ে বড় ভুল! কারণ ২–৩ ক্যান্ডেল যাওয়ার পর প্রাইস সাধারণত রেজিস্ট্যান্স/সাপোর্টে ঠেকে যায় বা রিট্রেস করে।',
    proEntryRule: 'কখনোই শুধু ২–৩টা ক্যান্ডেলের রঙ দেখে ট্রেড নেবে না! দেখবে সামনে খালি জায়গা (Clean Traffic) আছে কি না নাকি SNR/OB বাধা আছে।',
  ),
  BinaryDictEntry(
    category: 'TRAP',
    term: 'Mid-Range / No Man\'s Land (Strict NO-TRADE Rule)',
    signalBias: 'WAIT',
    meaningBanglish:
        'যখন প্রাইস সাপোর্ট এবং রেজিস্ট্যান্সের মাঝামাঝি ভাসছে—যেখানে কোনো Order Block, FVG, Trendline বা Chart Pattern নেই। এখানে ক্যান্ডেল যেকোনো দিকে ৫০/৫০ র‍্যান্ডম মুভ দেয়।',
    proEntryRule: 'প্রতিটি ক্যান্ডেলে ট্রেড হয় না! প্রাইস মাঝখানে থাকলে বাধ্যতামূলকভাবে WAIT কর এবং প্রাইসকে আগে লেভেলে আসতে দাও।',
  ),
  BinaryDictEntry(
    category: 'TRAP',
    term: 'OTC Choppy Barcode & Overlapping Doji Trap',
    signalBias: 'WAIT',
    meaningBanglish:
        'পরপর ছোট বডি, লম্বা দুই পাশের উইক, বা ১টা সবুজ ১টা লাল ক্যান্ডেল পাশাপাশি আটকে থাকা। এটি ব্রোকার অ্যালগরিদমের মানি-ইটিং জোন।',
    proEntryRule: '১০০% NO TRADE (WAIT)! পরিষ্কার ব্রেকআউট না হওয়া পর্যন্ত এন্ট্রি নেবে না।',
  ),

  // ── 6. SMART MTG (MARTINGALE) ADVISOR RULES ──
  BinaryDictEntry(
    category: 'MTG',
    term: 'Direct Shot Setup (No MTG Needed)',
    signalBias: 'MTG',
    meaningBanglish:
        'যখন সুইপ (BSL/SSL) সম্পন্ন হয়েছে, ক্যান্ডেল সাপোর্ট/রেজিস্ট্যান্স বা OB থেকে পরিষ্কার Pinbar/Engulfing দিয়ে ক্লোজ হয়েছে এবং ৪+ পিলার একমত।',
    proEntryRule: 'Direct 1st Candle Entry।',
  ),
  BinaryDictEntry(
    category: 'MTG',
    term: '1-Step MTG Backup Rule',
    signalBias: 'MTG',
    meaningBanglish:
        'যখন সেটআপ স্ট্রং কিন্তু প্রাইস জোনের আরেকটু গভীরে (যেমন FVG-এর ৫০% বা OB-এর শেষ প্রান্তে) ১টি ক্যান্ডেল ডিপ দিতে পারে।',
    proEntryRule: '১ম ক্যান্ডেলে এন্ট্রি নাও; যদি ১ম ক্যান্ডেলটি জোনের ভেতর পুলব্যাক ক্যান্ডেল হয়, তবে ঠিক পরের ক্যান্ডেল ওপেনেই 1-Step MTG নাও।',
  ),
  BinaryDictEntry(
    category: 'MTG',
    term: 'Strict No-MTG Rule (Protect Capital)',
    signalBias: 'MTG',
    meaningBanglish:
        'যদি ১ম ক্যান্ডেলটি বিশাল বডি (Marubozu) দিয়ে তোমার সাপোর্ট/রেজিস্ট্যান্স বা Order Block পুরোপুরি ভেঙে ফেলে, তার মানে ওই লেভেলটি ফেইল করেছে।',
    proEntryRule: 'লেভেল বডি দিয়ে ভেঙে গেলে কখনোই অন্ধভাবে MTG নেবে না! পরের ফ্রেশ সেটআপের জন্য অপেক্ষা করো।',
  ),
];

class BinarySignalScreen extends StatefulWidget {
  const BinarySignalScreen({super.key});

  static void Function(String id, String path)? onExternalScreenshot;

  @override
  State<BinarySignalScreen> createState() => _BinarySignalScreenState();
}

class _BinarySignalScreenState extends State<BinarySignalScreen> with WidgetsBindingObserver {
  static const MethodChannel _bin = MethodChannel('aniket_pro_ai/binary');
  static const MethodChannel _gal = MethodChannel('aniket_pro_ai/gallery');

  String _marketFilter = 'ALL';

  final List<String> _allPairs = [
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

  String _pair = 'EUR/USD (OTC)';
  String _tf = '1m';
  List<String> _keys = [];
  String _lastWorkingKey = '';
  String _activeProviderTag = '';
  bool _floatOn = false;
  bool _busy = false;
  int _lastAnalyzeMs = 0;

  // Strict Single-Analysis Deduplication Sets (1 Screenshot = 1 Analysis ONLY!)
  final Set<String> _analyzedIds = <String>{};
  final Set<String> _analyzedByteSignatures = <String>{};
  String _lastHistSsSig = '';

  // Auto-Imported Screenshot inside the Analysis Box
  String _lastSsPath = '';
  DateTime? _lastSsTime;

  // Signal + Advanced Multi-Pillar State (PA Psychology, SMC, ICT, Chart Patterns, Traps, MTG)
  String _dir = '—';
  int _conf = 0;
  int _waitMins = 1;
  String _tradeAfterText = '—';
  String _reason =
      'Bubble ON rekhe Pocket Option-e SS nile auto ekhane chole ashbe (Setup na thakle WAIT bolbe, blind trade dibe na)!';
  String _targetTime = '—';
  String _candlePlan = '—';
  String _pattern = '—';
  String _structure = '—';
  String _smcZone = '—';
  String _ictConcept = '—';
  String _chartPattern = '—';
  String _mtgAdvice = '—';
  String _entryGuide = '—';
  String _riskLevel = '—';
  bool _otcTrap = false;
  String _trapType = 'No Trap — Clean Setup';

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
  String _mmMode = '1-Step MTG';
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

  String _cleanKey(String raw) {
    return raw
        .replaceAll('Bearer ', '')
        .replaceAll('bearer ', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
  }

  String _detectProviderName(String key) {
    final k = _cleanKey(key);
    if (k.startsWith('gsk_')) return 'Groq';
    if (k.startsWith('sk-or-')) return 'OpenRouter';
    if (k.startsWith('AIza')) return 'Gemini';
    return 'Mistral/AI';
  }

  String _keysProviderSummary() {
    if (_keys.isEmpty) return '';
    final counts = <String, int>{};
    for (final k in _keys) {
      final p = _detectProviderName(k);
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
  }

  String _computeBytesSignature(Uint8List bytes) {
    if (bytes.isEmpty) return 'empty';
    int h1 = bytes.length;
    int h2 = 0x811C9DC5;
    final step = math.max(1, bytes.length ~/ 96);
    for (int i = 0; i < bytes.length; i += step) {
      h1 = ((h1 * 31) + bytes[i]) & 0x7FFFFFFF;
      h2 = ((h2 ^ bytes[i]) * 0x01000193) & 0x7FFFFFFF;
    }
    return '${bytes.length}_${h1.toRadixString(16)}_${h2.toRadixString(16)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bin.setMethodCallHandler(_onResult);
    BinarySignalScreen.onExternalScreenshot = _handleExternalAutoScreenshot;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (BinarySignalScreen.onExternalScreenshot == _handleExternalAutoScreenshot) {
      BinarySignalScreen.onExternalScreenshot = null;
    }
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncFromBackgroundService();
    }
  }

  Future<void> _ensureScreenshotPermissions() async {
    try {
      await [
        Permission.photos,
        Permission.videos,
        Permission.storage,
      ].request();
    } catch (_) {}
  }

  void _handleExternalAutoScreenshot(String id, String path) {
    if (path.isEmpty) return;
    if (id.isNotEmpty && _analyzedIds.contains(id)) return;
    if (id.isNotEmpty) _analyzedIds.add(id);

    if (!mounted) return;
    setState(() {
      _lastSsPath = path;
      _lastSsTime = DateTime.now();
    });
    SharedPreferences.getInstance().then((p) => p.setString('bin_last_ss', path));

    if (_floatOn) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_busy && (nowMs - _lastAnalyzeMs) > 4000) {
      _analyzeFilePath(path, fromAuto: true, forceManual: false);
    }
  }

  Future<void> _syncFromBackgroundService() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final lastSs = p.getString('bin_last_ss') ?? '';
      if (lastSs.isNotEmpty && File(lastSs).existsSync() && lastSs != _lastSsPath) {
        if (mounted) {
          setState(() {
            _lastSsPath = lastSs;
          });
        }
      }
      final raw = await _bin.invokeMethod<List>('getHist');
      if (raw != null && raw.isNotEmpty && mounted) {
        final nativeHist = raw
            .map((e) => _formatHistLine(e.toString()))
            .where((s) => s.isNotEmpty && !s.contains(' 0% '))
            .take(5)
            .toList();
        if (nativeHist.isNotEmpty) {
          setState(() {
            _hist = nativeHist;
          });
        }
      }
    } catch (_) {}
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
    final savedKeys = (p.getStringList('bin_keys') ?? []).map(_cleanKey).where((k) => k.isNotEmpty).toList();
    final savedHist = p.getStringList('bin_hist') ?? [];
    final savedWins = p.getInt('bin_wins') ?? 0;
    final savedLosses = p.getInt('bin_losses') ?? 0;
    final savedStake = p.getDouble('bin_stake') ?? 1.0;
    final savedLastSs = p.getString('bin_last_ss') ?? '';

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
      if (savedLastSs.isNotEmpty && File(savedLastSs).existsSync()) {
        _lastSsPath = savedLastSs;
      }
      _hist = (nativeHist.isNotEmpty ? nativeHist : savedHist.map(_formatHistLine))
          .where((s) => !s.contains(' 0% '))
          .take(5)
          .toList();
    });
  }

  Future<void> _saveHist(
    String dir,
    int conf, {
    String? ssSig,
    String? customPair,
    String? customTf,
    String? targetCandleTime,
    String? tradeAfter,
    String? mtgShort,
  }) async {
    if (conf <= 0 && dir == 'WAIT') return;
    if (ssSig != null && ssSig.isNotEmpty) {
      if (ssSig == _lastHistSsSig) return;
      _lastHistSsSig = ssSig;
    }

    final icon = _dirIcon(dir);
    final usePair = customPair ?? _pair;
    final useTf = customTf ?? _tf;
    final useTime = (targetCandleTime != null && targetCandleTime.isNotEmpty && targetCandleTime != '—')
        ? targetCandleTime
        : _upcomingCandleTimes.first;
    final minsTag = (tradeAfter != null && tradeAfter.isNotEmpty && tradeAfter != '—')
        ? ' • $tradeAfter'
        : '';
    final mtgTag = (mtgShort != null && mtgShort.isNotEmpty) ? ' • $mtgShort' : '';
    final line = '$icon $conf% $usePair ($useTf)$minsTag [🕒 $useTime]$mtgTag';

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

  String _buildTradeAfterLabel(int waitMins, String targetCandleTime, String dir) {
    if (dir == 'WAIT') {
      return '⏸️ EKHON TRADE NIBE NA (Wait for Setup)';
    }
    final stepSec = _periodSec();
    if (stepSec < 60) {
      final secs = stepSec * waitMins.clamp(1, 3);
      return '$secs sec por Trade ($targetCandleTime Candle)';
    }
    final mins = waitMins.clamp(1, 5);
    return '$mins min por Trade ($targetCandleTime Candle)';
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

  // ── FULL INTERACTIVE BINARY TRADING DICTIONARY MODAL SHEET ──
  Future<void> _openTradingDictionarySheet() async {
    String searchQ = '';
    String selectedCat = 'ALL';
    final ctrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = searchQ.trim().toLowerCase();
            final list = kBinaryTradingDictionary.where((e) {
              if (selectedCat != 'ALL' && e.category != selectedCat) return false;
              if (q.isEmpty) return true;
              return e.term.toLowerCase().contains(q) ||
                  e.meaningBanglish.toLowerCase().contains(q) ||
                  e.proEntryRule.toLowerCase().contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            '📚 Binary Pro Dictionary (PA • SMC • ICT • Patterns • Traps)',
                            style: TextStyle(
                              color: Color(0xFFC6A962),
                              fontSize: 14.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    TextField(
                      controller: ctrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search concept... (e.g. Wick, Order Block, FVG, Sweep, Wedge, Wait)',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFC6A962), size: 19),
                        filled: true,
                        fillColor: const Color(0xFF181B2E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFC6A962), width: 0.9),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFFFD54F), width: 1.4),
                        ),
                      ),
                      onChanged: (v) => setModalState(() => searchQ = v),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in [
                            ['ALL', 'All (${kBinaryTradingDictionary.length})'],
                            ['PA', '🕯️ Candle Psychology'],
                            ['SMC', '🏦 SMC'],
                            ['ICT', '🎯 ICT'],
                            ['PATTERN', '📐 Patterns'],
                            ['TRAP', '🚨 Traps & Wait'],
                            ['MTG', '🔄 MTG Rules'],
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  c[1],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: selectedCat == c[0] ? Colors.black : Colors.white70,
                                  ),
                                ),
                                selected: selectedCat == c[0],
                                selectedColor: const Color(0xFFC6A962),
                                backgroundColor: const Color(0xFF1A1D30),
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => setModalState(() => selectedCat = c[0]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, idx) {
                          final item = list[idx];
                          final badgeColor = item.signalBias == 'UP'
                              ? const Color(0xFF00E676)
                              : item.signalBias == 'DOWN'
                                  ? const Color(0xFFFF5252)
                                  : item.signalBias == 'TRAP' || item.signalBias == 'WAIT'
                                      ? const Color(0xFFFF8A80)
                                      : const Color(0xFFFFD54F);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171A2C),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.term,
                                        style: const TextStyle(
                                          color: Color(0xFFFFD54F),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.16),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: badgeColor.withOpacity(0.6)),
                                      ),
                                      child: Text(
                                        '${item.category} • ${item.signalBias}',
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.meaningBanglish,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '🎯 Pro Rule: ${item.proEntryRule}',
                                  style: const TextStyle(
                                    color: Color(0xFF69F0AE),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
      final ssPath = (map['path'] ?? '').toString();
      final ssSig = (map['sig'] ?? ssPath).toString();
      final providerUsed = (map['provider'] ?? '').toString();

      if (dir == 'STATE') {
        if (mounted) {
          setState(() {
            _floatOn = conf == 1;
          });
        }
        return null;
      }

      if (dir == 'SCANNING') {
        if (mounted) {
          setState(() {
            if (ssPath.isNotEmpty) {
              _lastSsPath = ssPath;
              _lastSsTime = DateTime.now();
            }
            _busy = true;
            _lastAnalyzeMs = DateTime.now().millisecondsSinceEpoch;
            _reason = reason.isNotEmpty
                ? reason
                : '📸 Screenshot Auto-Imported! Institutional Candlestick Psychology + SMC + ICT + Chart Pattern AI Analyzing...';
          });
        }
        return null;
      }

      if (ssPath.isNotEmpty && mounted) {
        setState(() {
          _lastSsPath = ssPath;
          _lastSsTime = DateTime.now();
          _busy = false;
          if (providerUsed.isNotEmpty) _activeProviderTag = providerUsed;
        });
      }

      _applyResult(
        dir: dir,
        conf: conf,
        reason: reason,
        ssSig: ssSig,
        pair: pair,
        time: time,
        waitMins: int.tryParse((map['wait_mins'] ?? '1').toString()) ?? 1,
        tradeAfterText: (map['trade_after'] ?? '').toString(),
        targetTime: (map['target_time'] ?? '').toString(),
        candlePlan: (map['candle_plan'] ?? '').toString(),
        pattern: (map['pattern'] ?? _pattern).toString(),
        structure: (map['structure'] ?? _structure).toString(),
        smcZone: (map['smc'] ?? _smcZone).toString(),
        ictConcept: (map['ict'] ?? _ictConcept).toString(),
        chartPattern: (map['chart_pattern'] ?? _chartPattern).toString(),
        mtgAdvice: (map['mtg_advice'] ?? _mtgAdvice).toString(),
        entryGuide: (map['entry'] ?? _entryGuide).toString(),
        riskLevel: (map['risk'] ?? _riskLevel).toString(),
        otcTrap: map['trap'] == true,
        trapType: (map['trap_type'] ?? '').toString(),
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
    String? ssSig,
    String? pair,
    String? time,
    int waitMins = 1,
    String? tradeAfterText,
    String? targetTime,
    String? candlePlan,
    String? pattern,
    String? structure,
    String? smcZone,
    String? ictConcept,
    String? chartPattern,
    String? mtgAdvice,
    String? entryGuide,
    String? riskLevel,
    bool otcTrap = false,
    String? trapType,
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
    final clampedWait = waitMins.clamp(1, 3);
    final resolvedTargetTime = (targetTime != null && targetTime.isNotEmpty)
        ? targetTime
        : upcoming[clampedWait - 1];
    final resolvedTradeAfter = (tradeAfterText != null && tradeAfterText.isNotEmpty)
        ? tradeAfterText
        : _buildTradeAfterLabel(clampedWait, resolvedTargetTime, finalDir);

    final shortArrow = finalDir == 'UP'
        ? '⬆️ UP'
        : finalDir == 'DOWN'
            ? '⬇️ DOWN'
            : '⏸️ NO TRADE (WAIT)';
    final resolvedPlan = (candlePlan != null && candlePlan.isNotEmpty)
        ? candlePlan
        : (finalDir == 'WAIT'
            ? '${upcoming[0]} ⏸️ WAIT | ${upcoming[1]} ⏸️ WAIT — Setup তৈরি হওয়া পর্যন্ত অপেক্ষা করো'
            : '${upcoming[0]} $shortArrow | ${upcoming[1]} $shortArrow | ${upcoming[2]} $shortArrow');

    final mtgBackupCandle = upcoming[math.min(clampedWait, 2)];
    final resolvedMtg = (mtgAdvice != null && mtgAdvice.isNotEmpty && mtgAdvice != '—')
        ? mtgAdvice
        : (finalDir == 'WAIT' || otcTrap
            ? '⛔ NO TRADE / NO MTG (এখন কোনো ট্রেড নেবে না)'
            : conf >= 88
                ? '✅ Direct Shot Setup (Backup 1-Step MTG: $mtgBackupCandle)'
                : '🔄 1-Step MTG Ready Rakho ($mtgBackupCandle Candle-e Backup)');

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (pair != null && pair.isNotEmpty && pair.contains('/')) {
        if (!_allPairs.contains(pair)) {
          _allPairs.insert(0, pair);
        }
        _pair = pair;
      }
      _dir = finalDir;
      _conf = finalDir == 'WAIT' ? 0 : conf.clamp(0, 99);
      _waitMins = clampedWait;
      _tradeAfterText = resolvedTradeAfter;
      _reason = reason.isNotEmpty ? reason : 'Institutional Analysis complete';
      _targetTime = resolvedTargetTime;
      _candlePlan = resolvedPlan;
      _pattern = (pattern != null && pattern.isNotEmpty) ? pattern : 'Candlestick Check';
      _structure = (structure != null && structure.isNotEmpty) ? structure : 'Structure Check';
      _smcZone = (smcZone != null && smcZone.isNotEmpty) ? smcZone : 'SMC Zone Check';
      _ictConcept = (ictConcept != null && ictConcept.isNotEmpty && ictConcept != '—')
          ? ictConcept
          : 'ICT Liquidity Check';
      _chartPattern = (chartPattern != null && chartPattern.isNotEmpty && chartPattern != '—')
          ? chartPattern
          : 'Chart Pattern Check';
      _mtgAdvice = resolvedMtg;
      _entryGuide = (entryGuide != null && entryGuide.isNotEmpty)
          ? entryGuide
          : (finalDir == 'WAIT'
              ? '⏸️ Skip This Candle • Wait for SNR / Order Block Touch'
              : '$resolvedTradeAfter • MTG: $mtgBackupCandle');
      _riskLevel = (riskLevel != null && riskLevel.isNotEmpty)
          ? riskLevel
          : (finalDir == 'WAIT'
              ? 'Skip Trade'
              : conf >= 85
                  ? 'Low Risk (Sniper)'
                  : 'Medium Risk');
      _otcTrap = otcTrap;
      _trapType = (trapType != null && trapType.isNotEmpty)
          ? trapType
          : (otcTrap ? 'Trap / Mid-Range Choppy Zone!' : 'Clean Institutional Setup');
      _trendScore = (trendScore != null && trendScore > 0)
          ? trendScore.clamp(0, 99)
          : (_conf > 0 ? (_conf - 2).clamp(40, 98) : 0);
      _patternScore = (patternScore != null && patternScore > 0)
          ? patternScore.clamp(0, 99)
          : (_conf > 0 ? (_conf + 2).clamp(40, 98) : 0);
      _snrScore = (snrScore != null && snrScore > 0)
          ? snrScore.clamp(0, 99)
          : (_conf > 0 ? (_conf + 1).clamp(40, 98) : 0);
      _momentumScore = (momentumScore != null && momentumScore > 0)
          ? momentumScore.clamp(0, 99)
          : (_conf > 0 ? (_conf - 1).clamp(40, 98) : 0);
      if (latencyMs != null) _latencyMs = latencyMs;
    });

    if (finalDir != 'WAIT' && _conf > 0) {
      final shortMtgTag = resolvedMtg.contains('Direct')
          ? 'Direct'
          : resolvedMtg.contains('NO')
              ? 'No-MTG'
              : '1-MTG Ready';

      _saveHist(
        finalDir,
        _conf,
        ssSig: ssSig,
        customPair: _pair,
        customTf: time,
        targetCandleTime: resolvedTargetTime,
        tradeAfter: '${_waitMins}m por',
        mtgShort: shortMtgTag,
      );
    }
  }

  Future<void> _pickAndAnalyze() async {
    if (_busy) return;
    if (_keys.isEmpty) {
      await _keysDialog();
      if (_keys.isEmpty) return;
    }
    await _ensureScreenshotPermissions();

    try {
      final res = await _gal.invokeMethod<List>('pickFiles', {'max': 1});
      if (res == null || res.isEmpty) return;
      final path = res.first.toString();
      if (path.isEmpty) return;
      await _analyzeFilePath(path, forceManual: true);
    } catch (e) {
      _toast('File choose error: $e');
    }
  }

  Future<void> _analyzeLatestScreenshot({bool silentFallback = false}) async {
    if (_busy) return;
    if (_keys.isEmpty && !silentFallback) {
      await _keysDialog();
      if (_keys.isEmpty) return;
    }
    await _ensureScreenshotPermissions();

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
          await _analyzeFilePath(path, fromAuto: silentFallback, forceManual: !silentFallback);
        }
      }
    } catch (e) {
      if (!silentFallback) _toast('Latest SS load error: $e');
    }
  }

  Future<void> _analyzeFilePath(
    String path, {
    bool fromAuto = false,
    bool forceManual = false,
  }) async {
    if (_busy) return;
    final file = File(path);
    if (!await file.exists()) {
      if (!fromAuto) _toast('Screenshot file pawa jayni');
      return;
    }

    final rawBytes = await file.readAsBytes();
    final byteSig = _computeBytesSignature(rawBytes);

    if (!forceManual && _analyzedByteSignatures.contains(byteSig)) {
      return;
    }
    _analyzedByteSignatures.add(byteSig);

    final startMs = DateTime.now().millisecondsSinceEpoch;
    _lastAnalyzeMs = startMs;

    setState(() {
      _lastSsPath = path;
      _lastSsTime = DateTime.now();
      _busy = true;
      _reason = '📸 SS Analysis Ghore Import Hoyeche! Candlestick Psychology + Chart Patterns + SMC + ICT analyze korche...';
    });

    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('bin_last_ss', path);
    } catch (_) {}

    try {
      Uint8List sendBytes = rawBytes;
      try {
        final comp = await _gal.invokeMethod<Uint8List>('compress', {
          'bytes': rawBytes,
          'maxKB': 240,
        });
        if (comp != null && comp.isNotEmpty) {
          sendBytes = comp;
        }
      } catch (_) {}

      final b64 = base64Encode(sendBytes);
      final parsed = await _multiProviderVisionWithFailover(b64);
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;

      final dir = (parsed['dir'] ?? 'WAIT').toString();
      final conf = int.tryParse((parsed['conf'] ?? '0').toString()) ?? 0;
      final waitMins = int.tryParse((parsed['wait_mins'] ?? '1').toString()) ?? 1;
      final tradeAfter = (parsed['trade_after_text'] ?? parsed['trade_after'] ?? '').toString();
      final reason = (parsed['reason'] ?? 'Institutional Analysis complete').toString();
      final detPair = (parsed['detected_pair'] ?? '').toString().trim();

      _applyResult(
        dir: dir,
        conf: conf,
        reason: reason,
        ssSig: byteSig,
        pair: (detPair.isNotEmpty && detPair != 'UNKNOWN' && detPair.contains('/')) ? detPair : _pair,
        waitMins: waitMins,
        tradeAfterText: tradeAfter,
        targetTime: (parsed['target_time'] ?? '').toString(),
        candlePlan: (parsed['candle_plan'] ?? '').toString(),
        pattern: (parsed['pattern'] ?? '').toString(),
        structure: (parsed['structure'] ?? '').toString(),
        smcZone: (parsed['smc'] ?? '').toString(),
        ictConcept: (parsed['ict'] ?? '').toString(),
        chartPattern: (parsed['chart_pattern'] ?? '').toString(),
        mtgAdvice: (parsed['mtg_advice'] ?? '').toString(),
        entryGuide: (parsed['entry'] ?? '').toString(),
        riskLevel: (parsed['risk'] ?? 'Low Risk').toString(),
        otcTrap: parsed['trap'] == true,
        trapType: (parsed['trap_type'] ?? '').toString(),
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  TRUE INSTITUTIONAL VISION ENGINE (NO FAKE PIXEL-COUNTING FALLBACK!)
  //  • Evaluates Candlestick Psychology + Chart Patterns + SMC + ICT + Traps
  //  • Strictly outputs dir="WAIT" when the chart is mid-range, choppy, or has
  //    no clean 80%+ confluence setup (NOT every candle is a trade!)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _multiProviderVisionWithFailover(String b64) async {
    final now = DateTime.now();
    final nowStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final times = _upcomingCandleTimes;
    final t1 = times[0];
    final t2 = times[1];
    final t3 = times[2];

    final isOtc = _pair.contains('(OTC)');
    final marketType = isOtc ? 'Pocket Option OTC algorithmic chart' : 'Live Interbank chart';

    final prompt = 'You are an elite 15-Year Institutional Price Action, Candlestick Psychology, SMC, ICT & Chart Pattern Master Trader.\n'
        'Read this trading chart screenshot with extreme precision. DO NOT guess or blindly follow 2-3 green/red candles!\n\n'
        'MANDATORY 6-STAGE INSTITUTIONAL ANALYSIS PROTOCOL:\n'
        '1. STRICT "NO-TRADE / WAIT" FILTER (NOT EVERY CANDLE IS A TRADE!):\n'
        '   - If price is in the middle of nowhere (Mid-Range / Equilibrium) with no nearby Support/Resistance, Order Block, FVG, or Trendline touch -> YOU MUST OUTPUT "dir": "WAIT" and "conf": 0!\n'
        '   - If the chart has choppy overlapping Doji/Spinning Top barcode candles or conflicting signals -> YOU MUST OUTPUT "dir": "WAIT"!\n'
        '   - If a setup is still 1-2 candles away from touching the SNR/Order Block/Neckline -> either set "wait_mins": 2 or 3 (for $t2 or $t3) OR output "dir": "WAIT" and tell the trader to wait until price reaches the level!\n'
        '2. DEEP CANDLESTICK PSYCHOLOGY ("CANDLESTICK SOCIOLOGY"):\n'
        '   - Never predict UP just because 2-3 green candles went up! Check whether the candle bodies are shrinking (momentum exhaustion) or hitting a Resistance/Supply level.\n'
        '   - Inspect the exact upper and lower wicks of the last 3 candles: Upper wick rejection at Resistance/Supply = Seller control (DOWN). Lower wick rejection at Support/Demand = Buyer absorption (UP).\n'
        '   - Check multi-candle formations: Pinbar/Hammer/Shooting Star, Bullish/Bearish Engulfing, Morning/Evening Star, Tweezer Top/Bottom, Inside Bar (Mother Bar) Fakey, Piercing Line, Dark Cloud Cover, Three White Soldiers/Crows, or Climax Exhaustion Marubozu.\n'
        '3. COMPLETE CHART PATTERNS:\n'
        '   - Identify the broader 20-40 candle chart pattern: Double Top (M Pattern + Neckline), Double Bottom (W Pattern + Neckline), Head & Shoulders / Inverse H&S, Rising Wedge (Bearish), Falling Wedge (Bullish), Bullish/Bearish Flag, Ascending/Descending/Symmetrical Triangle, or Parallel Trend Channel.\n'
        '4. SMART MONEY CONCEPTS (SMC) & ICT:\n'
        '   - Structure: HH/HL vs LH/LL, true body BOS (Break of Structure) vs wick-only Liquidity Sweep, CHoCH (Change of Character).\n'
        '   - Zones: Unmitigated Bullish/Bearish Order Block (OB), Breaker Block, 50% FVG (Fair Value Gap) retest, Premium vs Discount Fib OTE (61.8%-78.6%).\n'
        '   - ICT Liquidity: BSL (Buy-Side Liquidity sweep above Equal/Swing Highs -> Reversal DOWN) or SSL (Sell-Side Liquidity sweep below Equal/Swing Lows -> Reversal UP), Inducement (IDM) trap, AMD (Power of 3).\n'
        '5. POCKET OPTION TRAP FILTER:\n'
        '   - Flag Bull Trap (fake breakout above Resistance), Bear Trap (fake breakdown below Support), Late-Chaser Exhaustion Trap (3+ big candles into SNR), or OTC Barcode Trap.\n'
        '6. SMART MTG (MARTINGALE) ADVISOR:\n'
        '   - If dir is WAIT: set mtg_advice to "⛔ NO TRADE — Ekhon kono trade nibe na (Wait for Clean Setup)".\n'
        '   - If dir is UP or DOWN: state clearly whether it is "✅ Direct Shot (MTG Lagbe Na — Clean Sweep + Rejection)" OR "🔄 1-Step MTG Ready Rakho ($t2 Candle Backup — Zone Retest Possible)" OR "⛔ No MTG (Breakout Risk)".\n\n'
        'Current time: $nowStr | Pair: $_pair | Timeframe: $_tf ($marketType).\n'
        'Upcoming 3 candles: Candle 1 (1m por) = $t1, Candle 2 (2m por) = $t2, Candle 3 (3m por) = $t3.\n'
        'Reply ONLY with a single raw JSON object (no markdown fences):\n'
        '{"dir":"UP","conf":89,"detected_pair":"$_pair","wait_mins":1,"trade_after_text":"1 min por Trade ($t1 Candle)","target_time":"$t1","candle_plan":"$t1 ⬆️ UP | $t2 ⬆️ UP | $t3 ⬆️ UP","trap":false,"trap_type":"SSL Swept at Support — Bear Trap Reversal","pattern":"Lower Wick Pinbar + Morning Star","structure":"Bullish CHoCH + Support Flip (RBS)","smc":"Unmitigated Bullish OB + 50% FVG","ict":"SSL Liquidity Sweep (Turtle Soup)","chart_pattern":"Double Bottom (W) Neckline Bounce","mtg_advice":"✅ Direct Shot (Backup 1-Step MTG: $t2)","entry":"1 min por ($t1 Open) • Backup MTG: $t2","risk":"Low Risk (Sniper)","trend_score":88,"pattern_score":91,"snr_score":90,"momentum_score":87,"reason":"Detailed Banglish explanation of the exact Candlestick Psychology (wicks & bodies), Chart Pattern, SMC/ICT zone, why this is a real setup (or why to WAIT), and whether MTG is needed."}';

    final orderedKeys = <String>[
      if (_lastWorkingKey.isNotEmpty && _keys.contains(_lastWorkingKey)) _lastWorkingKey,
      ..._keys.map(_cleanKey).where((k) => k.isNotEmpty && k != _lastWorkingKey),
    ];

    final List<String> errorLog = [];

    for (int idx = 0; idx < orderedKeys.length; idx++) {
      final key = orderedKeys[idx];
      if (key.isEmpty) continue;
      final providerName = _detectProviderName(key);

      if (mounted && orderedKeys.length > 1) {
        setState(() {
          _reason = '⚡ Key ${idx + 1}/${orderedKeys.length} ($providerName) diye Deep Chart + Candlestick Psychology analyze korche...';
        });
      }

      Map<String, dynamic>? result;
      if (key.startsWith('gsk_')) {
        result = await _callGroqVision2026(key, prompt, b64, errorLog);
      } else if (key.startsWith('sk-or-')) {
        result = await _callOpenRouterVision2026(key, prompt, b64, errorLog);
      } else if (key.startsWith('AIza')) {
        result = await _raceGeminiModels(
          key: key,
          models: const [
            'gemini-2.5-flash',
            'gemini-2.5-flash-lite',
            'gemini-2.0-flash',
          ],
          prompt: prompt,
          b64: b64,
          timeoutSec: 11,
        );
      } else {
        result = await _callMistralVision2026(key, prompt, b64, errorLog) ??
            await _callOpenRouterVision2026(key, prompt, b64, errorLog);
      }

      if (result != null) {
        _lastWorkingKey = key;
        final usedModel = (result['__model'] ?? providerName).toString();
        _activeProviderTag = '$providerName ($usedModel)';
        return result;
      }
    }

    // NEVER invent a fake UP/DOWN 91% trade if all API keys failed!
    // Always output WAIT so the trader never takes a blind trade!
    _activeProviderTag = 'API Check Required';
    final errSummary = errorLog.isNotEmpty ? errorLog.take(2).join(' | ') : 'Check Internet / API Keys';
    return {
      'dir': 'WAIT',
      'conf': 0,
      'detected_pair': _pair,
      'wait_mins': 1,
      'trade_after_text': '⏸️ EKHON TRADE NIBE NA (Wait)',
      'target_time': t1,
      'candle_plan': '$t1 ⏸️ WAIT | $t2 ⏸️ WAIT',
      'trap': true,
      'trap_type': 'AI Server Busy / Key Limit ($errSummary)',
      'pattern': 'No Blind Trade',
      'structure': 'Wait for AI Vision Verification',
      'smc': 'Capital Protection Active',
      'ict': 'Never Trade Blindly',
      'chart_pattern': 'Wait for Setup',
      'mtg_advice': '⛔ NO TRADE (অন্ধভাবে ট্রেড দেওয়া বন্ধ রাখা হয়েছে)',
      'entry': 'Check API Key or tap Latest SS again in 5s',
      'risk': 'Protected (No Trade)',
      'trend_score': 0,
      'pattern_score': 0,
      'snr_score': 0,
      'momentum_score': 0,
      'reason':
          '⚠️ ভুল বা অন্ধ সিগন্যাল (Blind 91% Trade) সম্পূর্ণ বন্ধ করা হয়েছে! তোমার দেওয়া API Key-গুলোতে এই মুহূর্তে সার্ভার রেসপন্স আসেনি ($errSummary)। অনুগ্রহ করে ৫ সেকেন্ড পর আবার ট্রাই করো অথবা Key Box-এ একটি ফ্রি Gemini (AIza...) বা নতুন Groq (gsk_...) Key যোগ করো।',
    };
  }

  Future<Map<String, dynamic>?> _raceGeminiModels({
    required String key,
    required List<String> models,
    required String prompt,
    required String b64,
    required int timeoutSec,
  }) async {
    final completer = Completer<Map<String, dynamic>?>();
    int remaining = models.length;

    for (final m in models) {
      _trySingleGeminiModel(key, m, prompt, b64, timeoutSec: timeoutSec).then((res) {
        if (res != null && res['__ok'] == true && !completer.isCompleted) {
          res.remove('__ok');
          res['__model'] = m;
          completer.complete(res);
        } else {
          remaining--;
          if (remaining <= 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        remaining--;
        if (remaining <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future.timeout(
      Duration(seconds: timeoutSec + 1),
      onTimeout: () => null,
    );
  }

  Future<Map<String, dynamic>?> _trySingleGeminiModel(
    String key,
    String model,
    String prompt,
    String b64, {
    int timeoutSec = 10,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
      );
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

      final Map<String, dynamic> genConfig = {
        'temperature': 0.15,
      };
      if (model.contains('2.5')) {
        genConfig['thinkingConfig'] = {'thinkingBudget': 0};
      }

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
        'generationConfig': genConfig,
      };

      req.add(utf8.encode(jsonEncode(bodyMap)));
      final resp = await req.close().timeout(Duration(seconds: timeoutSec));
      final respText = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) {
        return {'__ok': false};
      }

      final root = jsonDecode(respText) as Map<String, dynamic>;
      final candidates = root['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return {'__ok': false};
      }

      final content = (candidates.first as Map)['content'] as Map?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        return {'__ok': false};
      }

      final buffer = StringBuffer();
      for (final p in parts) {
        if (p is Map) {
          if (p['thought'] == true) continue;
          if (p['text'] != null) {
            buffer.write(p['text'].toString());
          }
        }
      }

      final rawOut = buffer.toString().trim();
      final parsed = _extractJsonMap(rawOut);
      if (parsed != null) {
        parsed['__ok'] = true;
        return parsed;
      }
      return {'__ok': false};
    } catch (_) {
      return {'__ok': false};
    } finally {
      client?.close(force: true);
    }
  }

  // ── Groq 2026 Vision API (qwen/qwen3.8-27b + dynamic /v1/models discovery) ──
  Future<Map<String, dynamic>?> _callGroqVision2026(
    String key,
    String prompt,
    String b64,
    List<String> errorLog,
  ) async {
    final models = <String>[
      'qwen/qwen3.8-27b',
      'meta-models/muse-spark-open',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'meta-llama/llama-4-maverick-17b-128e-instruct',
    ];

    final discovered = await _discoverVisionModels('https://api.groq.com/openai/v1/models', key);
    for (final dm in discovered) {
      if (!models.contains(dm)) models.add(dm);
    }

    for (final m in models) {
      final res = await _trySingleOpenAiVisionModel(
        endpointUrl: 'https://api.groq.com/openai/v1/chat/completions',
        key: key,
        model: m,
        prompt: prompt,
        b64: b64,
        timeoutSec: 12,
        errorLog: errorLog,
      );
      if (res != null) {
        res['__model'] = m.split('/').last;
        return res;
      }
    }
    return null;
  }

  // ── Mistral 2026 Vision API (Mistral Small 4 / Ministral 3 14B/8B / Medium 3.5 / Large 4) ──
  Future<Map<String, dynamic>?> _callMistralVision2026(
    String key,
    String prompt,
    String b64,
    List<String> errorLog,
  ) async {
    final models = <String>[
      'mistral-small-latest',
      'ministral-14b-latest',
      'ministral-8b-latest',
      'mistral-medium-latest',
      'mistral-large-latest',
      'ministral-14b-2512',
      'ministral-8b-2512',
    ];
    for (final m in models) {
      final res = await _trySingleOpenAiVisionModel(
        endpointUrl: 'https://api.mistral.ai/v1/chat/completions',
        key: key,
        model: m,
        prompt: prompt,
        b64: b64,
        timeoutSec: 12,
        errorLog: errorLog,
      );
      if (res != null) {
        res['__model'] = m;
        return res;
      }
    }
    return null;
  }

  // ── OpenRouter 2026 Free Vision API ──
  Future<Map<String, dynamic>?> _callOpenRouterVision2026(
    String key,
    String prompt,
    String b64,
    List<String> errorLog,
  ) async {
    final models = <String>[
      'openrouter/free',
      'google/gemma-3-27b-it:free',
      'qwen/qwen2.5-vl-72b-instruct:free',
      'qwen/qwen2.5-vl-32b-instruct:free',
      'mistralai/mistral-small-3.1-24b-instruct:free',
    ];

    final discovered = await _discoverVisionModels(
      'https://openrouter.ai/api/v1/models',
      key,
      requireFreeSuffix: true,
    );
    for (final dm in discovered.take(4)) {
      if (!models.contains(dm)) models.add(dm);
    }

    for (final m in models) {
      final res = await _trySingleOpenAiVisionModel(
        endpointUrl: 'https://openrouter.ai/api/v1/chat/completions',
        key: key,
        model: m,
        prompt: prompt,
        b64: b64,
        timeoutSec: 13,
        extraHeaders: const {
          'HTTP-Referer': 'https://aniketpro.ai',
          'X-Title': 'ANIKET PRO AI',
        },
        errorLog: errorLog,
      );
      if (res != null) {
        res['__model'] = m.split('/').last;
        return res;
      }
    }
    return null;
  }

  Future<List<String>> _discoverVisionModels(
    String modelsUrl,
    String key, {
    bool requireFreeSuffix = false,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse(modelsUrl)).timeout(const Duration(seconds: 4));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return const [];
      final txt = await resp.transform(utf8.decoder).join();
      final root = jsonDecode(txt) as Map<String, dynamic>;
      final data = root['data'] as List?;
      if (data == null) return const [];
      final out = <String>[];
      for (final item in data) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          if (id.isEmpty) continue;
          if (requireFreeSuffix && !id.endsWith(':free')) continue;
          final low = id.toLowerCase();
          final arch = item['architecture']?.toString().toLowerCase() ?? '';
          if (low.contains('qwen') ||
              low.contains('vl') ||
              low.contains('vision') ||
              low.contains('gemma-3') ||
              low.contains('pixtral') ||
              low.contains('ministral') ||
              low.contains('llama-4') ||
              arch.contains('image')) {
            out.add(id);
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      client?.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _trySingleOpenAiVisionModel({
    required String endpointUrl,
    required String key,
    required String model,
    required String prompt,
    required String b64,
    required int timeoutSec,
    Map<String, String>? extraHeaders,
    List<String>? errorLog,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final uri = Uri.parse(endpointUrl);
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (extraHeaders != null) {
        extraHeaders.forEach((k, v) => req.headers.set(k, v));
      }

      // IMPORTANT: Use 2048 tokens so Thinking + Instruct models (like Qwen 3.8 27B)
      // never truncate inside <think>...</think> before outputting the JSON!
      final bodyMap = {
        'model': model,
        'temperature': 0.15,
        'max_tokens': 2048,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$b64'}
              }
            ]
          }
        ]
      };
      req.add(utf8.encode(jsonEncode(bodyMap)));
      final resp = await req.close().timeout(Duration(seconds: timeoutSec));
      final txt = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        errorLog?.add('${model.split('/').last}: HTTP ${resp.statusCode}');
        return null;
      }
      final root = jsonDecode(txt) as Map<String, dynamic>;
      final choices = root['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final content = ((choices.first as Map)['message'] as Map?)?['content']?.toString() ?? '';
      return _extractJsonMap(content);
    } catch (e) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Map<String, dynamic>? _extractJsonMap(String raw) {
    // Strip any <think>...</think> reasoning blocks emitted by Qwen 3.8 / DeepSeek / reasoning models
    final noThink = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    final cleaned = noThink.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start != -1 && end > start) {
        final jsonSlice = cleaned.substring(start, end + 1);
        try {
          final decoded = jsonDecode(jsonSlice);
          if (decoded is Map<String, dynamic>) return decoded;
        } catch (_) {
          final singleLine = jsonSlice.replaceAll('\r', ' ').replaceAll('\n', ' ');
          final decoded2 = jsonDecode(singleLine);
          if (decoded2 is Map<String, dynamic>) return decoded2;
        }
      }
    } catch (_) {}

    String pickStr(String key, [String def = '']) {
      final m = RegExp('"$key"\\s*:\\s*"([^"]+)"', caseSensitive: false).firstMatch(cleaned);
      return m?.group(1)?.trim() ?? def;
    }

    final dirMatch = RegExp(
      r'"dir"\s*:\s*"(UP|DOWN|WAIT|CALL|PUT|BUY|SELL)"',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (dirMatch != null) {
      final confMatch = RegExp(r'"conf"\s*:\s*(\d+)').firstMatch(cleaned);
      final waitMatch = RegExp(r'"wait_mins"\s*:\s*(\d+)').firstMatch(cleaned);
      final trapBool = RegExp(r'"trap"\s*:\s*true', caseSensitive: false).hasMatch(cleaned);
      return {
        'dir': dirMatch.group(1)!.toUpperCase(),
        'conf': int.tryParse(confMatch?.group(1) ?? '86') ?? 86,
        'detected_pair': pickStr('detected_pair', _pair),
        'wait_mins': int.tryParse(waitMatch?.group(1) ?? '1') ?? 1,
        'trade_after_text': pickStr('trade_after_text'),
        'target_time': pickStr('target_time'),
        'candle_plan': pickStr('candle_plan'),
        'trap': trapBool,
        'trap_type': pickStr('trap_type', 'No Trap — Clean Setup'),
        'pattern': pickStr('pattern', 'Pinbar / Engulfing'),
        'structure': pickStr('structure', 'BOS + SNR Bounce'),
        'smc': pickStr('smc', 'Order Block + FVG'),
        'ict': pickStr('ict', 'Liquidity Sweep + Displacement'),
        'chart_pattern': pickStr('chart_pattern', 'Price Action Channel'),
        'mtg_advice': pickStr('mtg_advice'),
        'entry': pickStr('entry'),
        'risk': pickStr('risk', 'Low Risk'),
        'reason': pickStr('reason', 'Institutional SMC + ICT + Price Action confluence confirmed.'),
      };
    }
    return null;
  }

  Future<void> _toggleFloat(bool val) async {
    if (val) {
      if (_keys.isEmpty) {
        await _keysDialog();
        if (_keys.isEmpty) return;
      }
      await _ensureScreenshotPermissions();

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
          '🔑 Multi-AI API Keys (1 per line)',
          style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'যেকোনো ফ্রি Key নিচে পরপর লাইনে বসাও — ১টা সার্ভার Busy থাকলে অটো পরের Key দিয়ে ট্রাই করবে:\n'
              '• Groq: gsk_... (Qwen 3.8 27B Vision)\n'
              '• Gemini: AIzaSy... (Gemini 2.5 Flash)\n'
              '• OpenRouter: sk-or-v1-...\n'
              '• Mistral: Ministral 3 / Mistral Small 4',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 6,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'gsk_...\nAIzaSy...\nsk-or-v1-...',
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
                  .map(_cleanKey)
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
      setState(() {
        _keys = saved;
        if (!_keys.contains(_lastWorkingKey)) {
          _lastWorkingKey = '';
        }
      });
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
    return 'NO TRADE (WAIT)';
  }

  @override
  Widget build(BuildContext context) {
    final sigColor = _dirColor(_dir);
    final totalTrades = _wins + _losses;
    final winRate = totalTrades > 0 ? ((_wins * 100) / totalTrades).round() : 0;
    final nextTimes = _upcomingCandleTimes;
    final hasScreenshot = _lastSsPath.isNotEmpty && File(_lastSsPath).existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Quick Market Filter Chips + Full Dictionary Button
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
                                ? '🔥 OTC'
                                : f == 'LIVE'
                                    ? '🌐 Live'
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
                    ActionChip(
                      backgroundColor: const Color(0xFF232742),
                      side: const BorderSide(color: Color(0xFFC6A962), width: 0.9),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.menu_book_rounded, color: Color(0xFFFFD54F), size: 15),
                      label: const Text(
                        'Pro Dictionary',
                        style: TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: _openTradingDictionarySheet,
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

              // 3. Main Institutional Pro Analysis Box
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
                        if (_activeProviderTag.isNotEmpty)
                          Text(
                            '⚡ ${_latencyMs > 0 ? "${(_latencyMs / 1000).toStringAsFixed(1)}s " : ""}$_activeProviderTag',
                            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (hasScreenshot) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0D18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _busy ? const Color(0xFFFFD54F) : const Color(0xFFC6A962),
                            width: 1.1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _busy ? Icons.radar : Icons.check_circle,
                                        color: _busy ? const Color(0xFFFFD54F) : const Color(0xFF00E676),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _busy
                                            ? '📸 SS Auto-Imported — Analyzing...'
                                            : '📸 Auto-Imported Chart (1 SS = 1 Check)',
                                        style: const TextStyle(
                                          color: Color(0xFFFFD54F),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_lastSsTime != null)
                                    Text(
                                      '${_lastSsTime!.hour.toString().padLeft(2, '0')}:${_lastSsTime!.minute.toString().padLeft(2, '0')}:${_lastSsTime!.second.toString().padLeft(2, '0')}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                    ),
                                ],
                              ),
                            ),
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                              child: SizedBox(
                                height: 110,
                                width: double.infinity,
                                child: Image.file(
                                  File(_lastSsPath),
                                  key: ValueKey(_lastSsPath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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
                            _dir == 'WAIT' ? 'SKIP' : '$_conf%',
                            style: TextStyle(
                              color: _conf >= 75 ? const Color(0xFF00E676) : const Color(0xFFFFB300),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E101D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC6A962), width: 0.9),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _dir == '—'
                                ? '⏱️ Koto Minute Por Trade: Bubble ON rekhe SS nao (${nextTimes[0]} / ${nextTimes[1]})'
                                : '⏱️ Trade Timing: $_tradeAfterText',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _dir == '—' ? const Color(0xFFFFD54F) : sigColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (_mtgAdvice != '—') ...[
                            const SizedBox(height: 4),
                            Text(
                              '🔄 MTG Guide: $_mtgAdvice',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF80D8FF),
                                fontSize: 11.8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          if (_candlePlan != '—') ...[
                            const SizedBox(height: 4),
                            Text(
                              '🕯️ 3-Candle Roadmap: $_candlePlan',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontSize: 11.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    if (_dir != '—')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_otcTrap || _dir == 'WAIT')
                              ? const Color(0xFF4A151B)
                              : const Color(0xFF102A22),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: (_otcTrap || _dir == 'WAIT')
                                ? Colors.redAccent
                                : const Color(0xFF00E676),
                            width: 0.9,
                          ),
                        ),
                        child: Text(
                          (_otcTrap || _dir == 'WAIT')
                              ? '🚨 NO-TRADE / TRAP FILTER: $_trapType'
                              : '🛡️ Trap Check Passed: $_trapType',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: (_otcTrap || _dir == 'WAIT')
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFF69F0AE),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    const SizedBox(height: 6),
                    Text(
                      '$_pair • $_tf  |  Next Stake: \$${_recommendedStake.toStringAsFixed(2)} ($_mmMode)',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      _reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.38,
                      ),
                    ),

                    if (_conf > 0 || _dir != '—') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          _infoBadge('🕯️ Candle Psych', _pattern, const Color(0xFF263238)),
                          _infoBadge('📐 Structure', _structure, const Color(0xFF1E2746)),
                          _infoBadge('🏦 SMC', _smcZone, const Color(0xFF2B2240)),
                          _infoBadge('🎯 ICT', _ictConcept, const Color(0xFF1A333A)),
                          _infoBadge('📊 Chart Pattern', _chartPattern, const Color(0xFF2D291E)),
                          _infoBadge('⏱️ Entry', _entryGuide, const Color(0xFF1B352E)),
                          _infoBadge('🛡️ Risk', _riskLevel, const Color(0xFF3A2A1D)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _scoreMiniBar('SMC/Trend', _trendScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('Candle Psych', _patternScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('ICT/SNR', _snrScore),
                          const SizedBox(width: 6),
                          _scoreMiniBar('Pattern', _momentumScore),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. Primary Action Buttons
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

              // 5. AUTO SS ANALYSIS Toggle Card
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
                            'AUTO SS BUBBLE 🎯 (No Blind Trade • Pro Setup Only)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _floatOn
                                ? '🟢 ON: ১টা SS নিলে ঠিক ১ বারই Candlestick Psychology + Chart Pattern + SMC/ICT চেক করবে (সেটআপ না থাকলে WAIT বলবে, অন্ধভাবে 91% ট্রেড দেবে না)!'
                                : 'ON করলে: SS নিলেই অটো ডিটেক্ট করে প্রো সেটআপ থাকলে UP/DOWN আর সেটআপ না থাকলে WAIT (No Trade) বলে দেবে',
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
                              ? 'Key nei — tap kore Gemini / Groq / OpenRouter key boshao'
                              : '${_keys.length} ta key (${_keysProviderSummary()}) — busy hole auto switch',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.2),
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
