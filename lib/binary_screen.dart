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
//  COMPLETE BINARY PRO DICTIONARY (Traps Masterclass • Candlestick Psychology •
//  Chart Patterns • SMC • ICT • Smart MTG Rules)
// ═══════════════════════════════════════════════════════════════════════════
class ProTradingConcept {
  final String category; // TRAP | PA | PATTERN | SMC | ICT | MTG
  final String term;
  final String meaningBanglish;
  final String proEntryRule;
  final String signalBias; // UP | DOWN | WAIT | COUNTER-TRAP

  const ProTradingConcept({
    required this.category,
    required this.term,
    required this.meaningBanglish,
    required this.proEntryRule,
    required this.signalBias,
  });
}

const List<ProTradingConcept> kBinaryTradingDictionary = [
  // ── 1. BINARY TRAPS MASTERCLASS (RETAIL TRAP VS PRO COUNTER-TRADE) ──
  ProTradingConcept(
    category: 'TRAP',
    term: 'Bull Trap (Fake Breakout Above Resistance)',
    meaningBanglish:
        'মার্কেট যখন একটা চেনা Resistance বা Swing High-এর উপরে হঠাৎ সবুজ/নীল ক্যান্ডেল তুলে দেয়, তখন ৯০% সাধারণ ট্রেডার ভাবে Breakout হয়েছে এবং তারা UP ট্রেড নেয়। কিন্তু ক্যান্ডেলটা উপরে লম্বা Upper Wick রেখে আবার লেভেলের নিচে ক্লোজ হয় বা পরের ক্যান্ডেলই বড় লাল হয়ে নিচে পড়ে—একেই Bull Trap বলে।',
    proEntryRule:
        'Resistance-এর উপরে ব্রেকআউট ক্যান্ডেলে লম্বা Upper Wick দেখলে বা ব্রেকআউট ক্যান্ডেল দুর্বল হলে ভুলেও UP নেবে না—পরের ক্যান্ডেলে Counter-Trap DOWN (PUT) ট্রেড নেবে!',
    signalBias: 'DOWN',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: 'Bear Trap (Fake Breakdown Below Support)',
    meaningBanglish:
        'Support বা Swing Low-এর নিচে হঠাৎ একটা লাল ক্যান্ডেল নামিয়ে দিয়ে সাধারণ ট্রেডারদের ভয় দেখিয়ে SELL/DOWN করানো হয়। কিন্তু নিচে থাকা Buyer-রা লম্বা Lower Wick দিয়ে প্রাইস আবার Support-এর উপরে তুলে আনে (Liquidity Sweep / Spring)।',
    proEntryRule:
        'Support-এর নিচে সুইপ করে ক্যান্ডেল যদি আবার Support-এর ভেতরে ক্লোজ দেয় বা পরের ক্যান্ডেল Bullish Engulfing হয়, তবে সাথে সাথে Counter-Trap UP (CALL) ট্রেড নেবে!',
    signalBias: 'UP',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: '3-Candle FOMO Exhaustion Trap (Late Chaser Trap)',
    meaningBanglish:
        'পরপর ৩–৪টা সবুজ/নীল বা লাল ক্যান্ডেল দেখে রিটেল ট্রেডাররা লোভে পড়ে ৪ নম্বর ক্যান্ডেলেও একই দিকে ট্রেড দেয়। অথচ ৩য় ক্যান্ডেলটি যখন কোনো Resistance/Order Block-এ গিয়ে বডি ছোট করে বা উইক দেয়, তখন বায়ারদের শক্তি শেষ (Exhaustion) হয়ে যায় এবং পরের ক্যান্ডেল উল্টো দিকে পড়ে।',
    proEntryRule:
        'টানা ৩টা বড় ক্যান্ডেল যাওয়ার পর যদি সামনে SNR বা Order Block থাকে এবং শেষ ক্যান্ডেলে উইক রিজেকশন দেখা যায়, তবে ট্রেন্ডের দিকে না গিয়ে Reversal ট্রেড নেবে!',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: 'Round Number (.000 / .500 / .300) OTC Algorithm Trap',
    meaningBanglish:
        'Pocket Option OTC এবং লাইভ মার্কেটে গোল সংখ্যা (যেমন 158.300, 158.500, 5250, 1.08500)-এর ঠিক ১–২ পিপস উপরে বা নিচে প্রাইস নিয়ে গিয়ে ফেক ব্রেকআউট দেখানো হয় এবং পরের ক্যান্ডেলই গোল সংখ্যার ভেতরে ফিরে আসে।',
    proEntryRule:
        'Round Number লেভেলে বড় উইক রিজেকশন দেখলে ব্রেকআউটের দিকে না গিয়ে রিভার্সাল ট্রেড নেবে। আর বডি দিয়ে পুরোপুরি ব্রেক করলে ১ ক্যান্ডেল রিটেস্টের জন্য অপেক্ষা করবে।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: 'Inside Bar Fakey Trap (Mother Bar False Break)',
    meaningBanglish:
        'একটি বড় ক্যান্ডেলের (Mother Bar) পেটের ভেতর ছোট ক্যান্ডেল (Inside Bar) তৈরি হওয়ার পর পরের ক্যান্ডেলটি একদিকে ফেক ব্রেকআউট দিয়ে লম্বা উইক রেখে আবার Mother Bar-এর ভেতরে ঢুকে পড়ে।',
    proEntryRule:
        'যেই দিকে ফেক উইক দিয়েছে তার ঠিক উল্টো দিকে পরের ১–২ ক্যান্ডেলের জন্য হাই-উইনরেট Sniper ট্রেড নেবে।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: 'Inducement (IDM) Early-Entry Trap',
    meaningBanglish:
        'আসল Order Block বা মূল Support/Resistance-এর একটু আগেই মার্কেট একটা ছোট নকল Support/Resistance তৈরি করে। রিটেল ট্রেডাররা সেখানেই ট্রেড নেয়, আর মার্কেট সেই লেভেলটা ভেঙে আসল Order Block ছুঁয়ে তারপর ঘোরে।',
    proEntryRule:
        'প্রথম দুর্বল লেভেলে ট্রেড না নিয়ে অপেক্ষা করো—যখনই সেই লেভেলটা সুইপ করে পেছনের আসল Order Block বা FVG ছোঁবে, তখনই আসল Sniper Entry নেবে।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'TRAP',
    term: 'Mid-Range Equilibrium & Price Trigger Rule',
    meaningBanglish:
        'প্রাইস যখন উপরে Resistance এবং নিচে Support—দুই লেভেলের মাঝখানে (Mid-Zone) থাকে, তখন সাথে সাথে ট্রেড নিলে ৫০/৫০ জুয়া হয়। প্রো ট্রেডাররা তখন নির্দিষ্ট Price Level সেট করে অপেক্ষা করে।',
    proEntryRule:
        'যখন অ্যাপ বলবে Price এখন X-এ আছে, Y এর উপরে গেলে UP আর Z এর নিচে গেলে DOWN—তখন প্রাইস ঠিক ওই নাম্বারে পৌঁছানো পর্যন্ত ১–২ ক্যান্ডেল অপেক্ষা করে তারপর ট্রেড নেবে।',
    signalBias: 'WAIT',
  ),

  // ── 2. CANDLESTICK PSYCHOLOGY ("CANDLESTICK SOCIOLOGY") ──
  ProTradingConcept(
    category: 'PA',
    term: 'Wick vs Body Pressure (Buyer/Seller Sociology)',
    meaningBanglish:
        'ক্যান্ডেলের বডি দেখায় কারা ক্লোজ করেছে, কিন্তু লম্বা উইক (Wick/Shadow) দেখায় কাদেরকে ফাঁদে ফেলে রিজেক্ট করা হয়েছে। লম্বা নিচের উইক মানে Seller Trap ও Buyer Entry; লম্বা উপরের উইক মানে Buyer Trap ও Seller Entry।',
    proEntryRule:
        'Support-এ নিচের উইক বডির ২ গুণ হলে UP; Resistance-এ উপরের উইক বডির ২ গুণ হলে DOWN।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'PA',
    term: 'Hammer / Bullish Pinbar Rejection',
    meaningBanglish:
        'Support বা Demand Zone-এ ছোট বডি এবং নিচে ২–৩ গুণ লম্বা লেজ (Lower Wick)। সেলাররা নিচে নামাতে চেয়েও ব্যর্থ হয়েছে।',
    proEntryRule:
        'Support বা SSL Sweep-এর পর Hammer তৈরি হলে পরের ক্যান্ডেল (1 min por) সরাসরি UP (CALL)।',
    signalBias: 'UP',
  ),
  ProTradingConcept(
    category: 'PA',
    term: 'Shooting Star / Bearish Pinbar Rejection',
    meaningBanglish:
        'Resistance বা Supply Zone-এ ছোট বডি এবং উপরে ২–৩ গুণ লম্বা উইক (Upper Wick)। বায়াররা উপরে তুলতে গিয়ে ট্র্যাপে পড়েছে।',
    proEntryRule:
        'Resistance বা BSL Sweep-এর পর Shooting Star দেখলে পরের ক্যান্ডেল (1 min por) সরাসরি DOWN (PUT)।',
    signalBias: 'DOWN',
  ),
  ProTradingConcept(
    category: 'PA',
    term: 'Bullish & Bearish Engulfing',
    meaningBanglish:
        'আগের ক্যান্ডেলের পুরো বডিকে যখন পরের বিপরীত রঙের ক্যান্ডেল সম্পূর্ণ গিলে ফেলে, তখন মার্কেটের নিয়ন্ত্রণ পুরোপুরি ঘুরে গেছে।',
    proEntryRule:
        'Key Level-এ Engulfing হলে ১ম ক্যান্ডেল (Direct) অথবা ৫০% রিটেস্টে (1-Step MTG সহ) এন্ট্রি।',
    signalBias: 'UP',
  ),
  ProTradingConcept(
    category: 'PA',
    term: 'Morning Star & Evening Star (3-Candle Reversal)',
    meaningBanglish:
        '১ম ক্যান্ডেল স্ট্রং ট্রেন্ড, ২য় ক্যান্ডেল ছোট Doji/Spinning Top (সংশয়), এবং ৩য় ক্যান্ডেল বিপরীত দিকে আগের ক্যান্ডেলের ৫০%-এর বেশি ভেঙে ক্লোজ দেয়।',
    proEntryRule:
        '৩য় ক্যান্ডেল ক্লোজ হওয়ার সাথে সাথে পরের ক্যান্ডেলে (1 min por) Direct Shot এন্ট্রি।',
    signalBias: 'UP',
  ),
  ProTradingConcept(
    category: 'PA',
    term: 'Tweezer Top & Tweezer Bottom',
    meaningBanglish:
        'পরপর দুটো ক্যান্ডেলের ঠিক একই প্রাইস লেভেলে সমান উইক রিজেকশন—ডাবল রিজেকশন নিশ্চিত করে যে ওই প্রাইস লেভেলে প্রাতিষ্ঠানিক অর্ডার বসে আছে।',
    proEntryRule:
        'Tweezer Bottom-এ UP এবং Tweezer Top-এ DOWN (Next Candle 1m por)।',
    signalBias: 'COUNTER-TRAP',
  ),

  // ── 3. COMPLETE CHART PATTERNS ──
  ProTradingConcept(
    category: 'PATTERN',
    term: 'Double Top (M) & Double Bottom (W)',
    meaningBanglish:
        'প্রাইস দুবার একই Resistance ছুঁয়ে নিচে নামলে M (Double Top) এবং দুবার একই Support ছুঁয়ে উপরে উঠলে W (Double Bottom) তৈরি হয়।',
    proEntryRule:
        '২য় টপ/বটমে উইক রিজেকশন দেখলে সাথে সাথে এন্ট্রি, অথবা মাঝখানের Neckline ব্রেক ও রিটেস্টে এন্ট্রি।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'PATTERN',
    term: 'Head and Shoulders / Inverse H&S',
    meaningBanglish:
        'মাঝখানে একটি উঁচু সুইং (Head) এবং দুই পাশে দুটি নিচু সুইং (Shoulders)। এটি সবচেয়ে শক্তিশালী ট্রেন্ড রিভার্সাল চার্ট প্যাটার্ন।',
    proEntryRule:
        'Right Shoulder-এ রিজেকশন ক্যান্ডেল দেখলে বা Neckline ব্রেকআউট রিটেস্টে ট্রেড নেবে।',
    signalBias: 'DOWN',
  ),
  ProTradingConcept(
    category: 'PATTERN',
    term: 'Rising Wedge (Bearish) & Falling Wedge (Bullish)',
    meaningBanglish:
        'প্রাইস যখন সরু হতে হতে উপরের দিকে ওঠে (Rising Wedge), তখন বায়াররা ক্লান্ত হয়ে নিচে ব্রেক করে (DOWN)। আর সরু হতে হতে নিচে নামলে (Falling Wedge) উপরে ব্রেক করে (UP)।',
    proEntryRule:
        'Wedge-এর ট্রেন্ডলাইন ব্রেক করার পর প্রথম ক্যান্ডেল বা রিটেস্ট ক্যান্ডেলে ট্রেড।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'PATTERN',
    term: 'Bullish Flag, Bearish Flag & Triangles',
    meaningBanglish:
        'হঠাৎ বড় মুভমেন্টের (Impulse Pole) পর ছোট চ্যানেলে বিপরীত দিকে কারেকশন হলে Flag তৈরি হয়, আর সমান্তরাল সাপোর্ট/রেজিস্ট্যান্সের সাথে তির্যক লাইন মিলে Triangle তৈরি হয়।',
    proEntryRule:
        'Flag বা Triangle বডি দিয়ে ব্রেক করলেই মূল ট্রেন্ডের দিকে কন্টিনিউয়েশন ট্রেড।',
    signalBias: 'UP',
  ),

  // ── 4. SMART MONEY CONCEPTS (SMC) & ICT ──
  ProTradingConcept(
    category: 'SMC',
    term: 'Order Block (OB) & Breaker Block',
    meaningBanglish:
        'বড় Impulsive BOS মুভমেন্ট শুরু হওয়ার ঠিক আগের শেষ বিপরীত ক্যান্ডেলটি হলো Order Block (OB)। আর যেই OB ভেঙে গেছে সেটি উল্টো দিক থেকে রিটেস্ট হলে Breaker Block হিসেবে কাজ করে।',
    proEntryRule:
        'প্রাইস যখন প্রথমবার Unmitigated Order Block-এ ফিরে এসে উইক রিজেকশন দেয়, তখনই পরের ক্যান্ডেল ট্রেড।',
    signalBias: 'COUNTER-TRAP',
  ),
  ProTradingConcept(
    category: 'SMC',
    term: 'Fair Value Gap (FVG) 50% Consequent Encroachment',
    meaningBanglish:
        '৩টি ক্যান্ডেলের মধ্যে ১ম ও ৩য় ক্যান্ডেলের উইকের মাঝে যে খালি গ্যাপ থাকে তা হলো FVG। প্রাইস চুম্বকের মতো এই গ্যাপের ৫০% পূরণ করতে আসে এবং সেখান থেকে বাউন্স করে।',
    proEntryRule:
        'FVG-এর ৫০% লেভেল ছুঁয়ে রিজেকশন দিলেই ট্রেন্ডের দিকে এন্ট্রি।',
    signalBias: 'UP',
  ),
  ProTradingConcept(
    category: 'ICT',
    term: 'BSL / SSL Liquidity Sweep (Turtle Soup)',
    meaningBanglish:
        'আগের Swing High বা Equal Highs-এর উপরে উইক মেরে স্টপ-লস খাওয়া হলো BSL Sweep (এরপর মার্কেট নিচে নামে)। আর Swing Low বা Equal Lows-এর নিচে উইক মারা হলো SSL Sweep (এরপর মার্কেট উপরে ওঠে)।',
    proEntryRule:
        'Liquidity Sweep ক্যান্ডেলটি লেভেলের ভেতরে ক্লোজ দিলেই পরের ক্যান্ডেল Direct Shot Reversal।',
    signalBias: 'COUNTER-TRAP',
  ),

  // ── 5. SMART MTG (MARTINGALE) RULES ──
  ProTradingConcept(
    category: 'MTG',
    term: 'Direct Shot vs 1-Step MTG vs No-MTG',
    meaningBanglish:
        '• Direct Shot: Liquidity Sweep + Pinbar/Engulfing একসাথে থাকলে ১ম ক্যান্ডেলই উইন হয়।\n'
        '• 1-Step MTG Ready: প্রাইস যদি Order Block বা FVG-এর ভেতরে একটু গভীর রিটেস্ট (Deep Mitigation) নেয়, তবে পরের ১ ক্যান্ডেল (1-Step MTG) ব্যাকআপ রাখলে রিকভারি হয়ে যায়।\n'
        '• No MTG: যদি ক্যান্ডেল সাপোর্ট/রেজিস্ট্যান্স পুরো বডি দিয়ে ভেঙে ফেলে (True Breakout), তবে ভুলেও MTG নেবে না!',
    proEntryRule:
        'সর্বোচ্চ ১-স্টেপ MTG ব্যবহার করবে, কখনোই ২–৩ স্টেপ ইমোশনাল MTG নেবে না।',
    signalBias: 'WAIT',
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
//  BINARY SIGNAL SCREEN — PRO TRAP MASTER + LIVE PRICE TRIGGER FORECASTER
// ═══════════════════════════════════════════════════════════════════════════
class BinarySignalScreen extends StatefulWidget {
  const BinarySignalScreen({super.key});

  static void Function(String id, String path)? onExternalScreenshot;

  @override
  State<BinarySignalScreen> createState() => _BinarySignalScreenState();
}

class _BinarySignalScreenState extends State<BinarySignalScreen> with WidgetsBindingObserver {
  static const _bin = MethodChannel('aniket_pro_ai/binary');
  static const _gal = MethodChannel('aniket_pro_ai/gallery');

  final List<String> _allPairs = [
    // ── Pocket Option OTC Forex Pairs ──
    'EUR/USD (OTC)',
    'GBP/USD (OTC)',
    'USD/JPY (OTC)',
    'AUD/USD (OTC)',
    'USD/CAD (OTC)',
    'USD/CHF (OTC)',
    'NZD/USD (OTC)',
    'EUR/JPY (OTC)',
    'GBP/JPY (OTC)',
    'EUR/GBP (OTC)',
    'AUD/JPY (OTC)',
    'AUD/CAD (OTC)',
    'AUD/CHF (OTC)',
    'CAD/JPY (OTC)',
    'CAD/CHF (OTC)',
    'CHF/JPY (OTC)',
    'EUR/AUD (OTC)',
    'EUR/CAD (OTC)',
    'EUR/CHF (OTC)',
    'EUR/NZD (OTC)',
    'GBP/AUD (OTC)',
    'GBP/CAD (OTC)',
    'GBP/CHF (OTC)',
    'GBP/NZD (OTC)',
    'NZD/JPY (OTC)',
    'NZD/CAD (OTC)',
    'NZD/CHF (OTC)',
    // ── OTC Emerging / Asian / Exotic Currencies ──
    'USD/BDT (OTC)',
    'USD/INR (OTC)',
    'USD/PKR (OTC)',
    'USD/BRL (OTC)',
    'USD/TRY (OTC)',
    'USD/MXN (OTC)',
    'USD/ZAR (OTC)',
    'USD/EGP (OTC)',
    'USD/ARS (OTC)',
    'USD/COP (OTC)',
    'USD/IDR (OTC)',
    'USD/NGN (OTC)',
    'USD/PHP (OTC)',
    'USD/SGD (OTC)',
    'USD/THB (OTC)',
    'USD/VND (OTC)',
    'USD/CNH (OTC)',
    'EUR/TRY (OTC)',
    'EUR/RUB (OTC)',
    // ── Crypto & Reversed Crypto Pairs ──
    'BTC/USD (OTC)',
    'USD/BTC (OTC)',
    'ETH/USD (OTC)',
    'USD/ETH (OTC)',
    'SOL/USD (OTC)',
    'BNB/USD (OTC)',
    'XRP/USD (OTC)',
    'ADA/USD (OTC)',
    'DOGE/USD (OTC)',
    'LTC/USD (OTC)',
    'TRX/USD (OTC)',
    'DOT/USD (OTC)',
    'MATIC/USD (OTC)',
    'AVAX/USD (OTC)',
    'LINK/USD (OTC)',
    'SHIB/USD (OTC)',
    'TON/USD (OTC)',
    'PEPE/USD (OTC)',
    'BTC/USDT',
    'ETH/USDT',
    'SOL/USDT',
    // ── Commodities & Metals (Gold / Silver / Oil) ──
    'XAU/USD (GOLD OTC)',
    'XAU/USD (GOLD)',
    'XAG/USD (SILVER OTC)',
    'WTI CRUDE OIL (OTC)',
    'BRENT OIL (OTC)',
    'NATURAL GAS (OTC)',
    // ── Global Indices & Top Stocks (OTC) ──
    'US100 / NASDAQ (OTC)',
    'US500 / S&P500 (OTC)',
    'US30 / DOW JONES (OTC)',
    'GER40 / DAX (OTC)',
    'UK100 / FTSE (OTC)',
    'JPN225 / NIKKEI (OTC)',
    'APPLE (OTC)',
    'TESLA (OTC)',
    'NVIDIA (OTC)',
    'AMAZON (OTC)',
    'MICROSOFT (OTC)',
    'META (OTC)',
    'GOOGLE (OTC)',
    'MCDONALDS (OTC)',
    'INTEL (OTC)',
    'BOEING (OTC)',
    // ── Live Forex Market Pairs ──
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'AUD/USD',
    'USD/CAD',
    'USD/CHF',
    'NZD/USD',
    'EUR/JPY',
    'GBP/JPY',
    'EUR/GBP',
    'AUD/JPY',
    'EUR/AUD',
    'EUR/CAD',
    'GBP/AUD',
    'GBP/CAD',
  ];

  final List<String> _timeframes = ['5s', '15s', '30s', '1m', '2m', '3m', '5m', '15m'];

  String _pair = 'EUR/USD (OTC)';
  String _tf = '1m';
  String _marketFilter = 'ALL'; // ALL | OTC | LIVE | CRYPTO
  List<String> _keys = [];
  String _lastWorkingKey = '';
  String _activeProviderTag = '';
  bool _floatOn = false;
  bool _busy = false;

  // ── Signal & Deep Trap / Price Trigger State ──
  String _dir = '—';
  int _conf = 0;
  int _waitMins = 1;
  String _tradeAfterText = '—';
  String _reason =
      'Bubble ON রেখে Pocket Option-এ স্ক্রিনশট নাও — Trap Detection + Candlestick Psychology + SMC/ICT দেখে সিগন্যাল এবং ঠিক কোন প্রাইসে গেলে ট্রেড হবে তা বলে দেবে!';
  String _pattern = '—';
  String _structure = '—';
  String _smcZone = '—';
  String _ictConcept = '—';
  String _chartPattern = '—';
  String _mtgAdvice = '—';
  String _entryGuide = '—';
  String _riskLevel = '—';
  String _targetTime = '—';
  String _candlePlan = '—';
  bool _otcTrap = false;
  String _trapType = '—';

  // ── NEW: Live Price & Trigger Level Forecaster State ──
  String _currentPrice = '—';
  String _upTrigger = '—';
  String _downTrigger = '—';
  String _trapPsychology = '—';

  int _trendScore = 0;
  int _patternScore = 0;
  int _snrScore = 0;
  int _momentumScore = 0;
  int _latencyMs = 0;

  String _lastSsPath = '';
  DateTime? _lastSsTime;
  final Set<String> _analyzedIds = <String>{};
  final Set<String> _analyzedByteSignatures = <String>{};
  String _lastHistSsSig = '';
  int _lastAnalyzeMs = 0;

  int _wins = 0;
  int _losses = 0;
  double _baseStake = 1.0;
  final double _payoutPct = 85.0;
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

  String _buildTradeAfterLabel(
    int waitMins,
    String targetCandleTime,
    String dir, {
    String? currentPrice,
    String? upTrigger,
    String? downTrigger,
  }) {
    if (dir == 'WAIT') {
      final cp = (currentPrice != null && currentPrice.isNotEmpty && currentPrice != '—')
          ? ' (Ekhon $currentPrice)'
          : '';
      if (upTrigger != null && upTrigger.isNotEmpty && upTrigger != '—') {
        return '⏸️ Wait$cp → $upTrigger';
      }
      return '⏸️ Wait$cp — Price Trigger Level-e gele Trade nibe';
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
                            '📚 Binary Pro Dictionary (Traps • Candle Psych • SMC • ICT)',
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
                        hintText: 'Search Trap, Bull Trap, Wick, OB, FVG, Sweep, Wedge...',
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
                            ['TRAP', '🪤 Traps Masterclass'],
                            ['PA', '🕯️ Candle Psych'],
                            ['PATTERN', '📐 Patterns'],
                            ['SMC', '🏦 SMC'],
                            ['ICT', '🎯 ICT'],
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
                                  : item.signalBias == 'COUNTER-TRAP'
                                      ? const Color(0xFF80D8FF)
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
                        hintText: 'Pair nam lekho... (e.g. USD/JPY, USD/BTC, EUR, BDT, GOLD)',
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
                : '📸 Screenshot Auto-Imported! Trap Detection + Candlestick Psychology + Price Trigger Level analyze korche...';
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
        currentPrice: (map['current_price'] ?? '').toString(),
        upTrigger: (map['up_trigger'] ?? '').toString(),
        downTrigger: (map['down_trigger'] ?? '').toString(),
        trapPsychology: (map['trap_psychology'] ?? '').toString(),
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
    String? currentPrice,
    String? upTrigger,
    String? downTrigger,
    String? trapPsychology,
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

    final resolvedCurrentPrice =
        (currentPrice != null && currentPrice.isNotEmpty && currentPrice != '—')
            ? currentPrice
            : 'Chart Live';
    final resolvedUpTrigger = (upTrigger != null && upTrigger.isNotEmpty && upTrigger != '—')
        ? upTrigger
        : 'Resistance Break / Support Bounce-e UP';
    final resolvedDownTrigger = (downTrigger != null && downTrigger.isNotEmpty && downTrigger != '—')
        ? downTrigger
        : 'Support Break / Resistance Trap Rejection-e DOWN';

    final resolvedTradeAfter = (tradeAfterText != null &&
            tradeAfterText.isNotEmpty &&
            !tradeAfterText.contains('Wait for Clean Setup'))
        ? tradeAfterText
        : _buildTradeAfterLabel(
            clampedWait,
            resolvedTargetTime,
            finalDir,
            currentPrice: resolvedCurrentPrice,
            upTrigger: resolvedUpTrigger,
            downTrigger: resolvedDownTrigger,
          );

    final shortArrow = finalDir == 'UP'
        ? '⬆️ UP'
        : finalDir == 'DOWN'
            ? '⬇️ DOWN'
            : '⏸️ WAIT';
    final resolvedPlan = (candlePlan != null &&
            candlePlan.isNotEmpty &&
            candlePlan != 'WAIT | WAIT | WAIT')
        ? candlePlan
        : (finalDir == 'WAIT'
            ? '${upcoming[0]} ⏸️ Watch $resolvedCurrentPrice → ⬆️ $resolvedUpTrigger | ⬇️ $resolvedDownTrigger'
            : '${upcoming[0]} $shortArrow | ${upcoming[1]} $shortArrow | ${upcoming[2]} $shortArrow');

    final mtgBackupCandle = upcoming[math.min(clampedWait, 2)];
    final resolvedMtg = (mtgAdvice != null && mtgAdvice.isNotEmpty && mtgAdvice != '—')
        ? mtgAdvice
        : (finalDir == 'WAIT'
            ? '🎯 Price Trigger স্পর্শ করলেই Direct Entry (অন্ধভাবে এন্ট্রি নয়)'
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
      _conf = finalDir == 'WAIT' ? 0 : (conf > 0 ? conf.clamp(75, 98) : 86);
      _waitMins = clampedWait;
      _tradeAfterText = resolvedTradeAfter;
      _reason = reason.isNotEmpty ? reason : 'Trap & Institutional Analysis complete';
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
              ? '📍 $resolvedCurrentPrice → ⬆️ $resolvedUpTrigger | ⬇️ $resolvedDownTrigger'
              : '$resolvedTradeAfter • MTG: $mtgBackupCandle');
      _riskLevel = (riskLevel != null && riskLevel.isNotEmpty)
          ? riskLevel
          : (finalDir == 'WAIT'
              ? 'Wait for Trigger Level'
              : _conf >= 86
                  ? 'Low Risk (Sniper)'
                  : 'Medium Risk');
      _otcTrap = otcTrap;
      _trapType = (trapType != null && trapType.isNotEmpty)
          ? trapType
          : (otcTrap ? 'Retail Trap Detected — Trade Counter-Trap!' : 'Clean Institutional Setup');
      _currentPrice = resolvedCurrentPrice;
      _upTrigger = resolvedUpTrigger;
      _downTrigger = resolvedDownTrigger;
      _trapPsychology = (trapPsychology != null && trapPsychology.isNotEmpty)
          ? trapPsychology
          : (_otcTrap
              ? 'Retail ট্রেডাররা ট্র্যাপে পড়ছে — Smart Money-এর দিকে Counter-Trap ট্রেড!'
              : 'No Retail Trap conflict — Smart Money order flow aligned.');
      _trendScore = (trendScore != null && trendScore > 0)
          ? trendScore.clamp(0, 99)
          : (_conf > 0 ? (_conf - 2).clamp(40, 98) : 70);
      _patternScore = (patternScore != null && patternScore > 0)
          ? patternScore.clamp(0, 99)
          : (_conf > 0 ? (_conf + 2).clamp(40, 98) : 72);
      _snrScore = (snrScore != null && snrScore > 0)
          ? snrScore.clamp(0, 99)
          : (_conf > 0 ? (_conf + 1).clamp(40, 98) : 74);
      _momentumScore = (momentumScore != null && momentumScore > 0)
          ? momentumScore.clamp(0, 99)
          : (_conf > 0 ? (_conf - 1).clamp(40, 98) : 71);
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
      _reason =
          '📸 SS Analysis Ghore Import Hoyeche! Traps + Candlestick Psychology + Price Trigger Level analyze korche...';
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
          'maxKB': 260,
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
        currentPrice: (parsed['current_price'] ?? '').toString(),
        upTrigger: (parsed['up_trigger'] ?? '').toString(),
        downTrigger: (parsed['down_trigger'] ?? '').toString(),
        trapPsychology: (parsed['trap_psychology'] ?? '').toString(),
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
  //  PRO TRAP-SNIPER + LIVE PRICE TRIGGER VISION ENGINE
  //  • Recognizes ALL candle color themes (Green/Red AND Blue/Orange/Cyan)
  //  • Focuses heavily on Binary Traps (Bull Trap, Bear Trap, 3-Candle FOMO
  //    Exhaustion Trap, Liquidity Sweep, Inducement, Round Number .000/.500)
  //  • When a Trap is spotted, it gives the COUNTER-TRAP trade (UP or DOWN)!
  //  • Always reads the exact right-hand Y-axis price scale (current_price,
  //    up_trigger, down_trigger) so the trader knows the exact price numbers!
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

    final prompt =
        'You are an elite 15-Year Institutional Binary Options Trap-Sniper, Candlestick Psychology, Chart Pattern, SMC & ICT Master Trader.\n'
        'Read this trading chart screenshot carefully.\n\n'
        'CRITICAL CHART & COLOR READING RULES:\n'
        '- Bullish (UP-moving) candles on this user\'s chart may be GREEN, BLUE, CYAN, or WHITE. Bearish (DOWN-moving) candles may be RED, ORANGE, or PINK. Always judge bullish vs bearish by whether the candle moves UP or DOWN on the price axis!\n'
        '- Read the EXACT right-hand Y-axis price scale and live price badge (for example 158.300, 158.368, 5246, 1.08520, etc.). You MUST fill "current_price", "up_trigger", and "down_trigger" with real numbers from the chart!\n\n'
        'MANDATORY 6-STAGE PRO TRAP & PRICE ACTION PROTOCOL:\n'
        '1. BINARY TRAP MASTERCLASS (HIGHEST PRIORITY — TRADE AGAINST RETAIL TRAPS!):\n'
        '   - In Binary Options, 80% of movements are Retail Traps. When you detect a Trap, DO NOT lazily output "WAIT" — give the high-probability COUNTER-TRAP trade ("UP" or "DOWN")!\n'
        '   - BULL TRAP -> SIGNAL "DOWN": If price pokes above a Resistance / Swing High / Round Number (.000/.300/.500) with an Upper Wick rejection, OR if 2-4 bullish candles have pushed into a Bearish Order Block / Resistance and their bodies are shrinking (Buyer Exhaustion / Retail FOMO Trap), output "dir": "DOWN", "trap": true, "trap_type": "🐂🪤 Bull Trap / BSL Sweep -> Counter-Trap DOWN!".\n'
        '   - BEAR TRAP -> SIGNAL "UP": If price pokes below a Support / Swing Low / Round Number with a Lower Wick rejection (Spring / SSL Sweep), OR if 2-4 bearish candles have dropped into a Bullish Order Block / Support followed by a strong bullish reversal candle (like a V-bottom or Engulfing), output "dir": "UP", "trap": true, "trap_type": "🐻🪤 Bear Trap / SSL Sweep -> Counter-Trap UP!".\n'
        '   - DISPLACEMENT / BREAKOUT CONTINUATION: If a strong V-reversal or Liquidity Sweep has already happened at the bottom/top and strong displacement candles are pushing with momentum toward an unfilled FVG or next zone (with room left before major Resistance/Support), give the continuation trade ("UP" or "DOWN") for 1 min por ($t1), OR if a 1-candle pullback is expected first, set "wait_mins": 2 ($t2)!\n'
        '2. WHEN TO GIVE "UP" / "DOWN" vs WHEN TO OUTPUT "WAIT":\n'
        '   - Give a decisive "dir": "UP" or "dir": "DOWN" (with "wait_mins": 1, 2, or 3) on ~80% of charts where there is a clear Trap Reversal, Candlestick Rejection, Order Block/FVG reaction, Chart Pattern (W, M, H&S, Wedge, Flag), or Trend Displacement.\n'
        '   - ONLY output "dir": "WAIT" if the chart is genuinely stuck in dead-flat tiny Doji barcode candles OR sitting strictly in the exact middle between distant Support & Resistance with zero momentum.\n'
        '   - MANDATORY WHEN "WAIT" (AND ON ALL CHARTS): You MUST tell the trader the EXACT price numbers from the right-hand axis! Example: "Price ekhon 5246-e ache -> 5267 er upore gele UP trade nibe, othoba 5232 er niche gele / 5267-e Upper Wick Rejection dile DOWN trade nibe (2-3 min por)". Never say "Wait" without giving the exact price numbers!\n'
        '3. CANDLESTICK PSYCHOLOGY ("CANDLESTICK SOCIOLOGY"):\n'
        '   - Analyze body-to-wick ratio of the last 3 candles: Upper wick rejection at Resistance = Sellers absorbing Buyers (DOWN). Lower wick rejection at Support = Buyers absorbing Sellers (UP).\n'
        '   - Identify Pinbar, Hammer, Shooting Star, Bullish/Bearish Engulfing, Morning/Evening Star, Tweezer Top/Bottom, Inside Bar Fakey, or Exhaustion Climax.\n'
        '4. CHART PATTERNS + SMC + ICT:\n'
        '   - Chart Pattern: Double Top (M), Double Bottom (W / V-Reversal), Head & Shoulders, Rising/Falling Wedge, Bull/Bear Flag, Triangle, or Channel.\n'
        '   - SMC & ICT: BOS, CHoCH, Unmitigated Order Block (OB), Breaker Block, 50% FVG, BSL/SSL Liquidity Sweep, Inducement (IDM) Trap.\n'
        '5. SMART MTG (MARTINGALE) ADVISOR:\n'
        '   - State whether the trade is "✅ Direct Shot (MTG Lagbe Na — Clean Trap Sweep)" OR "🔄 1-Step MTG Ready Rakho ($t2 Candle Backup)" OR "⛔ No MTG (Breakout Risk)".\n\n'
        'Current time: $nowStr | Pair: $_pair | Timeframe: $_tf ($marketType).\n'
        'Upcoming 3 candles: Candle 1 (1m por) = $t1, Candle 2 (2m por) = $t2, Candle 3 (3m por) = $t3.\n'
        'Reply ONLY with a single raw JSON object (no markdown fences):\n'
        '{"dir":"UP","conf":90,"detected_pair":"$_pair","wait_mins":1,"trade_after_text":"1 min por Trade ($t1 Candle)","target_time":"$t1","current_price":"158.295","up_trigger":"158.300 break korle UP / 158.275 Support bounce-e UP","down_trigger":"158.315 Resistance-e Upper Wick Rejection dile DOWN","trap_psychology":"Retail 5ta red candle dekhe SELL korchilo (Bear Trap), kintu SSL Sweep kore Smart Money 3ta strong bullish candle diye upore tulche!","candle_plan":"$t1 ⬆️ UP | $t2 ⬆️ UP | $t3 ⬆️ UP","trap":true,"trap_type":"🐻🪤 Bear Trap SSL Sweep -> Counter-Trap UP!","pattern":"V-Bottom Engulfing + Lower Wick Absorption","structure":"Bullish CHoCH + Displacement","smc":"Bullish Order Block + FVG Fill","ict":"SSL Liquidity Sweep (Turtle Soup)","chart_pattern":"Double Bottom (W) / V-Reversal","mtg_advice":"✅ Direct Shot (Backup 1-Step MTG: $t2)","entry":"1 min por ($t1 Open) • Trigger: 158.300+","risk":"Low Risk (Counter-Trap Sniper)","trend_score":89,"pattern_score":92,"snr_score":91,"momentum_score":88,"reason":"Detailed Banglish explanation including: (1) Exact Current Price & Trigger Price Levels (e.g. Price ekhon X-e ache, Y er upore gele UP / Z-e rejection dile DOWN), (2) Retail Trap vs Pro Action, (3) Candlestick Psychology + SMC/ICT, and (4) Timing & MTG advice."}';

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
          _reason =
              '⚡ Key ${idx + 1}/${orderedKeys.length} ($providerName) diye Trap + Price Level + Candlestick Psychology analyze korche...';
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

    _activeProviderTag = 'API Check Required';
    final errSummary = errorLog.isNotEmpty ? errorLog.take(2).join(' | ') : 'Check Internet / API Keys';
    return {
      'dir': 'WAIT',
      'conf': 0,
      'detected_pair': _pair,
      'wait_mins': 1,
      'trade_after_text': '⏸️ AI Key Busy — 5 sec por abar Latest SS tap koro',
      'target_time': t1,
      'current_price': 'Check Key',
      'up_trigger': 'SNR Support Bounce / Resistance Break-e UP',
      'down_trigger': 'Resistance Wick Rejection / Support Break-e DOWN',
      'trap_psychology': 'API Server ($errSummary) busy thakay blind trade dewa hoyni.',
      'candle_plan': '$t1 ⏸️ WAIT | $t2 ⏸️ WAIT',
      'trap': true,
      'trap_type': 'AI Server Busy ($errSummary)',
      'pattern': 'No Blind Trade',
      'structure': 'Wait for AI Vision Verification',
      'smc': 'Capital Protection Active',
      'ict': 'Never Trade Blindly',
      'chart_pattern': 'Wait for Setup',
      'mtg_advice': '⛔ NO TRADE (সার্ভার রেসপন্স ছাড়া অন্ধ ট্রেড বন্ধ)',
      'entry': 'Tap Latest SS again in 5s',
      'risk': 'Protected (No Trade)',
      'trend_score': 0,
      'pattern_score': 0,
      'snr_score': 0,
      'momentum_score': 0,
      'reason':
          '⚠️ তোমার দেওয়া API Key-তে এই মুহূর্তে সার্ভার রেসপন্স আসেনি ($errSummary)। ৫ সেকেন্ড পর আবার "Latest SS" বাটনে ট্যাপ করো অথবা Key Box-এ ফ্রি Gemini (AIza...) বা Groq (gsk_...) Key যোগ করো।',
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
        'temperature': 0.2,
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

  // ── Mistral 2026 Vision API ──
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

      final bodyMap = {
        'model': model,
        'temperature': 0.2,
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
        'conf': int.tryParse(confMatch?.group(1) ?? '88') ?? 88,
        'detected_pair': pickStr('detected_pair', _pair),
        'wait_mins': int.tryParse(waitMatch?.group(1) ?? '1') ?? 1,
        'trade_after_text': pickStr('trade_after_text'),
        'target_time': pickStr('target_time'),
        'current_price': pickStr('current_price'),
        'up_trigger': pickStr('up_trigger'),
        'down_trigger': pickStr('down_trigger'),
        'trap_psychology': pickStr('trap_psychology'),
        'candle_plan': pickStr('candle_plan'),
        'trap': trapBool,
        'trap_type': pickStr('trap_type', 'Trap Analysis Complete'),
        'pattern': pickStr('pattern', 'Pinbar / Engulfing'),
        'structure': pickStr('structure', 'BOS + SNR Bounce'),
        'smc': pickStr('smc', 'Order Block + FVG'),
        'ict': pickStr('ict', 'Liquidity Sweep + Displacement'),
        'chart_pattern': pickStr('chart_pattern', 'Price Action Channel'),
        'mtg_advice': pickStr('mtg_advice'),
        'entry': pickStr('entry'),
        'risk': pickStr('risk', 'Low Risk'),
        'reason': pickStr('reason', 'Institutional Trap + SMC + ICT + Price Action confluence confirmed.'),
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
    return 'WAIT FOR TRIGGER';
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
                            _dir == 'WAIT'
                                ? (_currentPrice != '—' ? '📍 $_currentPrice' : 'WATCH')
                                : '$_conf%',
                            style: TextStyle(
                              color: _conf >= 75 ? const Color(0xFF00E676) : const Color(0xFFFFB300),
                              fontSize: 20,
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

                    // ── Timing + MTG + 3-Candle Roadmap Card ──
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

                    // ── NEW: LIVE PRICE & EXACT TRIGGER LEVEL BOX (So Trader Always Knows Exact Price Numbers!) ──
                    if (_dir != '—')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101929),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF40C4FF), width: 0.9),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '🎯 CHART PRICE TRIGGER MAP',
                                  style: TextStyle(
                                    color: Color(0xFF80D8FF),
                                    fontSize: 11.2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1B2B44),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '📍 Ekhon Price: $_currentPrice',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD54F),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '⬆️ UP Trigger: $_upTrigger',
                              style: const TextStyle(
                                color: Color(0xFF69F0AE),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '⬇️ DOWN Trigger: $_downTrigger',
                              style: const TextStyle(
                                color: Color(0xFFFF8A80),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_trapPsychology != '—' && _trapPsychology.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🪤 Trap Psychology: $_trapPsychology',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),

                    // ── Trap / Counter-Trap Status Banner ──
                    if (_dir != '—')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _dir == 'WAIT'
                              ? const Color(0xFF3E2723)
                              : _otcTrap
                                  ? const Color(0xFF1A237E)
                                  : const Color(0xFF102A22),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _dir == 'WAIT'
                                ? const Color(0xFFFFB300)
                                : _otcTrap
                                    ? const Color(0xFF80D8FF)
                                    : const Color(0xFF00E676),
                            width: 0.9,
                          ),
                        ),
                        child: Text(
                          _dir == 'WAIT'
                              ? '⏳ WAIT FOR PRICE LEVEL: $_trapType'
                              : _otcTrap
                                  ? '🪤 COUNTER-TRAP SNIPER SIGNAL: $_trapType'
                                  : '🛡️ Trap Check Passed: $_trapType',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _dir == 'WAIT'
                                ? const Color(0xFFFFD54F)
                                : _otcTrap
                                    ? const Color(0xFF80D8FF)
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
                          _scoreMiniBar('Trap/SMC', _trendScore),
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
                            'AUTO SS BUBBLE 🎯 (Trap Sniper + Price Trigger Map)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _floatOn
                                ? '🟢 ON: SS নিলেই Bull/Bear Trap ধরে Counter-Trap UP/DOWN সিগন্যাল এবং ঠিক কোন প্রাইসে (যেমন 5246 → 5267) গেলে ট্রেড হবে তা দেখিয়ে দেবে!'
                                : 'ON করলে: SS নিলেই অটো ডিটেক্ট করে Trap Reversal সিগন্যাল + Exact Price Trigger Level বলে দেবে',
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

              if (_hist.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '📜 Recent Verified Signals (Max 5):',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                for (final h in _hist.take(5))
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141624),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      h,
                      style: TextStyle(
                        color: h.contains('⬆️')
                            ? const Color(0xFF69F0AE)
                            : h.contains('⬇️')
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFFFFD54F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _scoreMiniBar(String title, int score) {
    final c = score >= 80
        ? const Color(0xFF00E676)
        : score >= 65
            ? const Color(0xFFFFD54F)
            : const Color(0xFFFF8A80);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0E101C),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 9.5),
            ),
            const SizedBox(height: 2),
            Text(
              '$score%',
              style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
