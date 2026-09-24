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

  test('clear forgets the tracks', () async {
    final library =
        LibraryController(api: FakeTracksApi([_song]), token: () => 'tok');
    await library.load();

    library.clear();

    expect(library.tracks, isEmpty);
    expect(library.status, LibraryStatus.loading);
  });

  test('without a session nothing is requested', () async {
    final api = FakeTracksApi([_song]);
    final library = LibraryController(api: api, token: () => null);

    expect(await library.load(), isFalse);
    expect(api.calls, isEmpty);
  });
}
