import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/data/audio_cache.dart';
import 'package:path_provider/path_provider.dart';

const defaultCacheBytes = 500 * 1024 * 1024;

const _extensions = {
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/aac': 'aac',
  'audio/flac': 'flac',
  'audio/ogg': 'ogg',
  'audio/wav': 'wav',
  'audio/webm': 'webm',
};

/// Caches played tracks in the app's temporary directory, which the OS may
/// also clear. Files are named by track ID, never by the presigned URL, which
/// changes on every request. When the cache would exceed [maxBytes], the
/// least recently played tracks are deleted first.
class FileAudioCache implements AudioCache {
  FileAudioCache(this._directory, {this.maxBytes = defaultCacheBytes});

  final Future<Directory> Function() _directory;
  final int maxBytes;

  @override
  Future<AudioSource> sourceFor(Track track, Uri url) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final extension = _extensions[track.contentType] ?? 'audio';
    final file = File('${directory.path}/${track.id}.$extension');
    if (await file.exists()) {
      // A complete earlier download: play it offline and mark it recent.
      await file.setLastModified(DateTime.now());
      return AudioSource.file(file.path, tag: track.id);
    }
    await evict(directory, incomingBytes: track.sizeBytes, keep: track.id);
    // Streams the URL while writing the file (as .part until complete).
    // Experimental in just_audio, but the only built-in way to stream and
    // cache at once; it is isolated here so it is easy to replace.
    // ignore: experimental_member_use
    return LockCachingAudioSource(url, cacheFile: file, tag: track.id);
  }

  /// Deletes least recently used tracks until [incomingBytes] more fit.
  Future<void> evict(
    Directory directory, {
    int incomingBytes = 0,
    String? keep,
  }) async {
    final entries = <String, _Entry>{};
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final id = name.split('.').first;
      final stat = await entity.stat();
      final entry = entries.putIfAbsent(id, () => _Entry(id));
      entry.files.add(entity);
      entry.bytes += stat.size;
      if (stat.modified.isAfter(entry.lastUsed)) entry.lastUsed = stat.modified;
    }
    var total = entries.values.fold<int>(0, (sum, e) => sum + e.bytes);
    final oldestFirst = entries.values.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final entry in oldestFirst) {
      if (total + incomingBytes <= maxBytes) break;
      if (entry.id == keep) continue;
      for (final file in entry.files) {
        try {
          await file.delete();
        } on FileSystemException {
          // Still open by the player; it will be retried next time.
        }
      }
      total -= entry.bytes;
    }
  }

  @override
  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _Entry {
  _Entry(this.id);

  final String id;
  final files = <File>[];
  int bytes = 0;
  DateTime lastUsed = DateTime.fromMillisecondsSinceEpoch(0);
}

AudioCache createAudioCache() => FileAudioCache(() async =>
    Directory('${(await getTemporaryDirectory()).path}/nafir_audio_cache'));
