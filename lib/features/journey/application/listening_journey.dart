import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nafir/features/library/data/track.dart';

/// Account-scoped progress on this device. No listening data is published.
class ListeningJourney extends ChangeNotifier {
  ListeningJourney({FlutterSecureStorage? storage, DateTime Function()? now})
      : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  String? _account;
  int _generation = 0;
  bool ready = false;
  bool enabled = true;
  bool saveFailed = false;
  String _week = '';
  final Set<String> _weekly = {};
  final Set<String> _discovered = {};
  final Map<String, Map<String, int>> _months = {};
  Future<void> _writes = Future.value();

  DateTime get today => _now();
  static String monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
  static String weekKey(DateTime date) {
    // The Persian week starts on Saturday. UTC arithmetic avoids DST jumps.
    final day = DateTime.utc(date.year, date.month, date.day);
    return day
        .subtract(Duration(days: (date.weekday + 1) % 7))
        .toIso8601String()
        .substring(0, 10);
  }

  int get discoveries => _discovered.length;
  int get weeklyCount => _week == weekKey(today) ? _weekly.length : 0;
  bool heardThisWeek(String id) =>
      _week == weekKey(today) && _weekly.contains(id);
  Map<String, int> get monthlyPlays =>
      Map.unmodifiable(_months[monthKey(today)] ?? const <String, int>{});

  /// Switching accounts immediately hides the previous account's progress.
  Future<void> selectAccount(String? id) async {
    if (_account == id && ready) return;
    final generation = ++_generation;
    _account = id;
    ready = false;
    enabled = true;
    saveFailed = false;
    _week = '';
    _weekly.clear();
    _discovered.clear();
    _months.clear();
    notifyListeners();
    if (id == null) return;
    try {
      await _writes;
      final raw = await _storage.read(key: 'nafir.journey.$id');
      if (generation != _generation) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        enabled = data['enabled'] != false;
        _week = data['week'] as String? ?? '';
        _weekly.addAll((data['weekly'] as List).cast<String>());
        _discovered.addAll((data['discovered'] as List).cast<String>());
        final months = data['months'] as Map<String, dynamic>;
        for (final entry in months.entries) {
          _months[entry.key] = (entry.value as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, value as int),
          );
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage never blocks the player.
      if (generation != _generation) return;
      _week = '';
      _weekly.clear();
      _discovered.clear();
      _months.clear();
      saveFailed = true;
    }
    if (generation != _generation) return;
    ready = true;
    notifyListeners();
  }

  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
    _save();
  }

  /// Called only by PlayerController's meaningful-listen callback.
  void record(Track track) {
    if (!ready || !enabled || _account == null) return;
    final week = weekKey(today);
    if (_week != week) {
      _week = week;
      _weekly.clear();
    }
    _weekly.add(track.id);
    _discovered.add(track.id);
    final month = _months.putIfAbsent(monthKey(today), () => {});
    month.update(track.id, (count) => count + 1, ifAbsent: () => 1);
    final keys = _months.keys.toList()..sort();
    for (final key in keys.take((keys.length - 12).clamp(0, keys.length))) {
      _months.remove(key);
    }
    notifyListeners();
    _save();
  }

  List<Track> suggestions(List<Track> library) {
    final tracks = library.where((track) => !heardThisWeek(track.id)).toList();
    final plays = monthlyPlays;
    tracks.sort((a, b) {
      final count = (plays[a.id] ?? 0).compareTo(plays[b.id] ?? 0);
      return count != 0 ? count : a.id.compareTo(b.id);
    });
    return tracks.take(5).toList();
  }

  void _save() {
    final id = _account;
    if (id == null || !ready) return;
    final generation = _generation;
    final raw = jsonEncode({
      'enabled': enabled,
      'week': _week,
      'weekly': _weekly.toList(),
      'discovered': _discovered.toList(),
      'months': _months,
    });
    _writes = _writes.then((_) async {
      try {
        await _storage.write(key: 'nafir.journey.$id', value: raw);
        if (generation == _generation) saveFailed = false;
      } catch (_) {
        if (generation == _generation) saveFailed = true;
      }
    });
    unawaited(_writes);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @visibleForTesting
  Future<void> get saved => _writes;
}
