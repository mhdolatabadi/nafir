import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/data/audio_cache_io.dart';

Track _track(String id, {int size = 100, String type = 'audio/mpeg'}) =>
    Track(id: id, title: id, contentType: type, sizeBytes: size);

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('nafir_cache'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> put(String name, int bytes, int ageMinutes) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List.filled(bytes, 0));
    await file.setLastModified(
        DateTime.now().subtract(Duration(minutes: ageMinutes)));
  }

  List<String> names() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('a new track streams to a file named by track id, not URL', () async {
    final cache = FileAudioCache(() async => dir, maxBytes: 1000);
    final source = await cache.sourceFor(_track('t1', type: 'audio/mp4'),
        Uri.parse('https://x/nafir-music/k?X-Amz-Signature=abc'));

    // ignore: experimental_member_use
    expect(source, isA<LockCachingAudioSource>());
    // ignore: experimental_member_use
    final file = await (source as LockCachingAudioSource).cacheFile;
    expect(file.path, '${dir.path}/t1.m4a');
  });

  test('a completed download is played from disk and marked recent', () async {
    await put('t1.mp3', 10, 60);
    final cache = FileAudioCache(() async => dir, maxBytes: 1000);

    final source = await cache.sourceFor(_track('t1'), Uri.parse('https://x/'));

    expect(source, isA<ProgressiveAudioSource>());
    expect((source as UriAudioSource).uri.toFilePath(), '${dir.path}/t1.mp3');
    final age = DateTime.now()
        .difference(File('${dir.path}/t1.mp3').lastModifiedSync());
    expect(age.inMinutes, lessThan(1));
  });

  test('least recently played tracks are evicted to stay under the limit',
      () async {
    await put('old.mp3', 400, 30);
    await put('old.mp3.mime', 10, 30);
    await put('mid.mp3', 400, 20);
    await put('new.mp3', 100, 10);
    final cache = FileAudioCache(() async => dir, maxBytes: 1000);

    // 910 cached + 300 incoming > 1000: the oldest (old.*) must go.
    await cache.sourceFor(_track('next', size: 300), Uri.parse('https://x/'));

    expect(names(), ['mid.mp3', 'new.mp3']);
  });

  test('evicts as many as needed and never the track being played', () async {
    await put('a.mp3', 400, 30);
    await put('b.mp3', 400, 20);
    await put('keep.mp3.part', 150, 40);
    final cache = FileAudioCache(() async => dir, maxBytes: 500);

    await cache.evict(dir, incomingBytes: 300, keep: 'keep');

    expect(names(), ['keep.mp3.part']);
  });

  test('size counts every cached file, partial downloads included', () async {
    final cache = FileAudioCache(() async => dir);
    expect(await cache.sizeBytes(), 0);

    await put('a.mp3', 300, 1);
    await put('a.mp3.mime', 10, 1);
    await put('b.m4a.part', 50, 1);

    expect(await cache.sizeBytes(), 360);
  });

  test('size of a cache that was never created is zero', () async {
    final cache = FileAudioCache(() async => Directory('${dir.path}/none'));
    expect(await cache.sizeBytes(), 0);
    await cache.clear();
  });

  test('clear empties the cache but keeps the track being played', () async {
    await put('a.mp3', 10, 1);
    await put('a.mp3.mime', 10, 1);
    await put('playing.mp3.part', 10, 1);
    final cache = FileAudioCache(() async => dir);

    await cache.clear(keep: 'playing');

    expect(names(), ['playing.mp3.part']);
    await cache.clear();
    expect(names(), isEmpty);
    expect(await cache.sizeBytes(), 0);
  });
}
