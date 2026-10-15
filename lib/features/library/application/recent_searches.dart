import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nafir/core/search_text.dart';

/// Where recent searches are kept between launches.
abstract interface class RecentSearchesStore {
  Future<List<String>> read();
  Future<void> write(List<String> searches);
}

class SecureRecentSearchesStore implements RecentSearchesStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'nafir.recent_searches';

  @override
  Future<List<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const [];
    final value = jsonDecode(raw);
    return value is List ? [for (final item in value) '$item'] : const [];
  }

  @override
  Future<void> write(List<String> searches) =>
      _storage.write(key: _key, value: jsonEncode(searches));
}

class MemoryRecentSearchesStore implements RecentSearchesStore {
  MemoryRecentSearchesStore([List<String> initial = const []])
      : value = List.of(initial);

  List<String> value;

  @override
  Future<List<String>> read() async => List.of(value);

  @override
  Future<void> write(List<String> searches) async => value = List.of(searches);
}

/// The library searches the user ran, newest first, without repeats.
class RecentSearchesController extends ChangeNotifier {
  RecentSearchesController({RecentSearchesStore? store})
      : _store = store ?? SecureRecentSearchesStore();

  /// How many searches are remembered.
  static const limit = 8;

  final RecentSearchesStore _store;
  List<String> _items = const [];
  Future<void> _writes = Future.value();
  bool _changed = false;
  bool _disposed = false;

  List<String> get items => _items;

  Future<void> load() async {
    try {
      final saved = await _store.read();
      // A search added while reading wins over the saved list.
      if (_disposed || _changed) return;
      _items = List.unmodifiable(_clean(saved));
      notifyListeners();
    } catch (error) {
      debugPrint('Recent searches unavailable: $error');
    }
  }

  /// Puts [query] first; an equal earlier search (ignoring case, spacing
  /// and Persian/Arabic letter forms) is replaced by it.
  void add(String query) {
    final text = query.trim();
    if (normalizeForSearch(text).isEmpty) return;
    _set(_clean([text, ..._items]));
  }

  void remove(String query) => _set([
        for (final item in _items)
          if (item != query) item
      ]);

  void clear() => _set(const []);

  static List<String> _clean(List<String> searches) {
    final seen = <String>{};
    return [
      for (final search in searches)
        if (search.trim().isNotEmpty && seen.add(normalizeForSearch(search)))
          search.trim(),
    ].take(limit).toList();
  }

  void _set(List<String> items) {
    if (listEquals(items, _items)) return;
    _changed = true;
    _items = List.unmodifiable(items);
    notifyListeners();
    _writes = _writes.then((_) => _store.write(_items)).catchError(
        (Object error) => debugPrint('Could not save recent searches: $error'));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
