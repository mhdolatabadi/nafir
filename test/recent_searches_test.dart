import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/library/application/recent_searches.dart';

void main() {
  test('newest first, without repeats in any letter form or case', () {
    final recent = RecentSearchesController(store: MemoryRecentSearchesStore());
    recent
      ..add('  Debussy ')
      ..add('کلاسیک')
      ..add('DEBUSSY')
      // Arabic letter forms match their Persian twins.
      ..add('كلاسيك')
      ..add('   ');
    expect(recent.items, ['كلاسيك', 'DEBUSSY']);
  });

  test('keeps the latest ${RecentSearchesController.limit}', () {
    final recent = RecentSearchesController(store: MemoryRecentSearchesStore());
    for (var i = 0; i < 12; i++) {
      recent.add('search $i');
    }
    expect(recent.items, hasLength(RecentSearchesController.limit));
    expect(recent.items.first, 'search 11');
    expect(recent.items.last, 'search 4');
  });

  test('saves changes, reads them back, and removes or clears', () async {
    final store = MemoryRecentSearchesStore(['saved']);
    final recent = RecentSearchesController(store: store);
    await recent.load();
    expect(recent.items, ['saved']);

    recent.add('new');
    await pumpEventQueue();
    expect(store.value, ['new', 'saved']);

    recent.remove('saved');
    await pumpEventQueue();
    expect(store.value, ['new']);

    recent.clear();
    await pumpEventQueue();
    expect(recent.items, isEmpty);
    expect(store.value, isEmpty);
  });

  test('a search added while loading is not lost', () async {
    final recent =
        RecentSearchesController(store: MemoryRecentSearchesStore(['older']));
    final loading = recent.load();
    recent.add('typed');
    await loading;
    expect(recent.items, ['typed']);
  });
}
