import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Colours ──────────────────────────────────────────────────────────────
const Color kGold      = Color(0xFFF5E6C8);
const Color kBg        = Color(0xFF121212);
const Color kLoginBtn  = Color(0xFFEF4030);

// ── Constants ────────────────────────────────────────────────────────────
const String kUrl = 'https://aniketsarker.netlify.app';
const String kSheetUrl =
    'https://script.google.com/macros/s/AKfycbysLY93ie5plvuUrv42-E9vxG9IWcDImkuj-fUv3jg4tqSvyPcz0H1yZlkrocNFIiDO/exec';
const String kMasterKey = 'atp1726';
const MethodChannel galleryChannel    = MethodChannel('aniket_pro_ai/gallery');
const MethodChannel screenshotChannel = MethodChannel('aniket_pro_ai/screenshot');

// ── HTTP helpers ─────────────────────────────────────────────────────────
Future<String> httpGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 10));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<bool> httpPost(String url, Map<String, String> fields) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    req.write(fields.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}
