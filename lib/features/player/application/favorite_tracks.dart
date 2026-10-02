import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where liked track ids are kept between launches.
abstract interface class FavoritesStore {
  Future<Set<String>> read();
  Future<void> write(Set<String> ids);
}

/// Keeps likes on this device, next to the session token.
class SecureFavoritesStore implements FavoritesStore {
  SecureFavoritesStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'nafir.favorite_tracks';

  final FlutterSecureStorage _storage;

  @override
  Future<Set<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is List ? {...decoded.whereType<String>()} : {};
  }

  @override
  Future<void> write(Set<String> ids) =>
      _storage.write(key: _key, value: jsonEncode(ids.toList()));
}

class MemoryFavoritesStore implements FavoritesStore {
  MemoryFavoritesStore([Set<String>? ids]) : ids = {...?ids};

  Set<String> ids;

  @override
  Future<Set<String>> read() async => {...ids};

  @override
  Future<void> write(Set<String> ids) async => this.ids = {...ids};
}

/// The tracks the listener liked from the now-playing screen.
class FavoriteTracks extends ChangeNotifier {
  FavoriteTracks({FavoritesStore? store})
      : _store = store ?? MemoryFavoritesStore();

  final FavoritesStore _store;
  Set<String> _ids = {};

  bool contains(String trackId) => _ids.contains(trackId);

  /// Restores saved likes; ones made before it finishes are kept.
  Future<void> load() async {
    try {
      final saved = await _store.read();
      _ids = {...saved, ..._ids};
      notifyListeners();
    } catch (error) {
      debugPrint('Favorites unavailable: $error');
    }
  }

  /// Likes or unlikes [trackId]. The heart flips at once; a failed save is
  /// only logged, since the like still holds for this session.
  Future<void> toggle(String trackId) async {
    _ids = {..._ids};
    if (!_ids.remove(trackId)) _ids.add(trackId);
    notifyListeners();
    try {
      await _store.write(_ids);
    } catch (error) {
      debugPrint('Could not save favorites: $error');
    }
  }
}
