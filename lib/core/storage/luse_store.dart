import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/luse/models/luse_market_snapshot.dart';
import '../../features/luse/models/luse_company_profile.dart';

class LuseStore {
  static const _enabledKey = 'luse_enabled';
  static const _watchlistKey = 'luse_watchlist';
  static const _historyKey = 'luse_history';
  static const _lastFetchKey = 'luse_last_fetch';
  static const _lastNotifiedKey = 'luse_last_notified';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<List<String>> getWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_watchlistKey) ?? [];
  }

  Future<void> setWatchlist(List<String> symbols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_watchlistKey, symbols);
  }

  Future<void> addToWatchlist(String symbol) async {
    final list = await getWatchlist();
    if (!list.contains(symbol)) {
      list.add(symbol);
      await setWatchlist(list);
    }
  }

  Future<void> removeFromWatchlist(String symbol) async {
    final list = await getWatchlist();
    list.remove(symbol);
    await setWatchlist(list);
  }

  Future<List<LuseMarketSnapshot>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(LuseMarketSnapshot.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSnapshot(LuseMarketSnapshot snapshot) async {
    final history = await getHistory();
    history.removeWhere((s) => s.dateKey == snapshot.dateKey);
    history.add(snapshot);
    history.sort((a, b) => a.date.compareTo(b.date));
    if (history.length > 90) {
      history.removeRange(0, history.length - 90);
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history.map((s) => s.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
    await prefs.setInt(_lastFetchKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastFetchTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_lastFetchKey);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove(_lastFetchKey);
  }

  String _computeFingerprint(LuseMarketSnapshot snapshot) {
    final buffer = StringBuffer()
      ..write(snapshot.dateKey)
      ..write(':${snapshot.stocks.length}');
    for (final s in snapshot.stocks) {
      buffer.write('|${s.symbol}:${s.lastPrice}:${s.change}');
    }
    return buffer.toString();
  }

  Future<bool> hasSnapshotChanged(LuseMarketSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastNotifiedKey);
    final current = _computeFingerprint(snapshot);
    return last != current;
  }

  Future<void> markSnapshotNotified(LuseMarketSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNotifiedKey, _computeFingerprint(snapshot));
  }

  static const _profilePrefix = 'luse_profile_';

  Future<LuseCompanyProfile?> getCompanyProfile(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_profilePrefix$symbol');
    if (raw == null) return null;
    try {
      return LuseCompanyProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCompanyProfile(LuseCompanyProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_profilePrefix${profile.symbol}',
      jsonEncode(profile.toJson()),
    );
  }

  Future<void> clearCompanyProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_profilePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
