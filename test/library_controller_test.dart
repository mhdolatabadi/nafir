import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/data/track.dart';

import 'upload_controller_test.dart' show FakeTracksApi;

const _song =
    Track(id: 's1', title: 'Song', contentType: 'audio/mpeg', sizeBytes: 1000);

void main() {
  test('first load goes from loading to the server list', () async {
    final library =
        LibraryController(api: FakeTracksApi([_song]), token: () => 'tok');
    final seen = <LibraryStatus>[];
    library.addListener(() => seen.add(library.status));

    expect(await library.load(), isTrue);

    expect(seen.first, LibraryStatus.loading);
    expect(library.status, LibraryStatus.loaded);
    expect(library.tracks.single.title, 'Song');
    expect(library.usedBytes, 1000);
    expect(library.limitBytes, 5 * 1024 * 1024 * 1024);
  });

  test('a failed first load is an error; retry recovers', () async {
    final api = FakeTracksApi([_song])..listError = Exception('offline');
    final library = LibraryController(api: api, token: () => 'tok');

    expect(await library.load(), isFalse);
    expect(library.status, LibraryStatus.error);

    api.listError = null;
    expect(await library.load(), isTrue);
    expect(library.tracks, hasLength(1));
  });

  test('a failed refresh keeps the tracks already shown', () async {
    final api = FakeTracksApi([_song]);
    final library = LibraryController(api: api, token: () => 'tok');
    await library.load();

    api.listError = Exception('offline');
    expect(await library.load(), isFalse);

    expect(library.status, LibraryStatus.loaded);
    expect(library.tracks, hasLength(1));
  });

  test('deleting removes a track from the visible library', () async {
    final api = FakeTracksApi([_song]);
    final library = LibraryController(api: api, token: () => 'tok');
    await library.load();

    expect(await library.deleteTrack('s1'), isTrue);

    expect(api.deleted, ['s1']);
    expect(library.tracks, isEmpty);
    expect(library.usedBytes, 0);
    expect(library.isDeleting('s1'), isFalse);
  });

  test('a failed delete keeps the track and clears busy state', () async {
    final api = FakeTracksApi([_song])..deleteError = Exception('offline');
    final library = LibraryController(api: api, token: () => 'tok');
    await library.load();

    expect(await library.deleteTrack('s1'), isFalse);

    expect(library.tracks, [_song]);
    expect(library.isDeleting('s1'), isFalse);
  });

  test('clear forgets the tracks', () async {
    final library =
        LibraryController(api: FakeTracksApi([_song]), token: () => 'tok');
    await library.load();

    library.clear();

    expect(library.tracks, isEmpty);
    expect(library.usedBytes, 0);
    expect(library.limitBytes, 0);
    expect(library.status, LibraryStatus.loading);
  });

  test('without a session nothing is requested', () async {
    final api = FakeTracksApi([_song]);
    final library = LibraryController(api: api, token: () => null);

    expect(await library.load(), isFalse);
    expect(api.calls, isEmpty);
  });

  group('while bot imports are in progress', () {
    late List<(Duration, void Function())> scheduled;
    late int cancelled;
    late FakeTracksApi api;
    late LibraryController library;

    setUp(() {
      scheduled = [];
      cancelled = 0;
      api = FakeTracksApi([_song])..importsInProgress = 2;
      library = LibraryController(
        api: api,
        token: () => 'tok',
        schedule: (delay, callback) {
          scheduled.add((delay, callback));
          return () => cancelled++;
        },
      );
    });

    test('the library is checked again, less and less often', () async {
      await library.load();
      expect(library.importsInProgress, 2);
      expect(scheduled.single.$1, importPollDelays[0]);

      scheduled.single.$2();
      await Future<void>.delayed(Duration.zero);
      expect(api.calls.where((c) => c == 'list'), hasLength(2));
      expect(scheduled[1].$1, importPollDelays[1]);
    });

    test('polling stops when the imports finish', () async {
      await library.load();
      api
        ..importsInProgress = 0
        ..tracks.add(const Track(
            id: 'imported',
            title: 'From Bale',
            contentType: 'audio/mpeg',
            sizeBytes: 1,
            source: 'bale'));
      scheduled.single.$2();
      await Future<void>.delayed(Duration.zero);

      expect(library.importsInProgress, 0);
      expect(library.tracks.map((t) => t.id), contains('imported'));
      expect(library.tracks.last.importedFrom, 'بله');
      expect(scheduled, hasLength(1));
    });

    test('polling gives up after the last delay', () async {
      for (var i = 0; i <= importPollDelays.length; i++) {
        await library.load();
      }
      expect(scheduled, hasLength(importPollDelays.length));
    });

    test('clearing the library cancels polling', () async {
      await library.load();
      library.clear();
      expect(cancelled, 1);
      expect(library.importsInProgress, 0);
    });
  });
}
