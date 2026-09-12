import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Lưu session vào shared_preferences (một key JSON).
class SessionStore {
  static const _key = 'tb_session';

  Future<AppSession?> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return null;
    return AppSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AppSession s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(s.toJson()));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
