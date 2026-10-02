import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/player/application/favorite_tracks.dart';

class _FailingStore implements FavoritesStore {
  @override
  Future<Set<String>> read() => Future.error(Exception('locked'));

  @override
  Future<void> write(Set<String> ids) => Future.error(Exception('locked'));
}

void main() {
  test('likes persist and load back', () async {
    final store = MemoryFavoritesStore();
    final favorites = FavoriteTracks(store: store);

    await favorites.toggle('a');
    await favorites.toggle('b');
    await favorites.toggle('a');
    expect(store.ids, {'b'});

    final restored = FavoriteTracks(store: store);
    await restored.load();
    expect(restored.contains('b'), isTrue);
    expect(restored.contains('a'), isFalse);
  });

  test('a like made while loading is not lost', () async {
    final store = MemoryFavoritesStore({'saved'});
    final favorites = FavoriteTracks(store: store);
    final loading = favorites.load();
    await favorites.toggle('new');
    await loading;
    expect(favorites.contains('saved'), isTrue);
    expect(favorites.contains('new'), isTrue);
  });

  test('a broken store keeps likes for the session', () async {
    final favorites = FavoriteTracks(store: _FailingStore());
    await favorites.load();
    await favorites.toggle('a');
    expect(favorites.contains('a'), isTrue);
  });
}
