import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/track.dart';

class AndroidLocalAudioLibrary implements LocalAudioLibrary {
  static const _channel =
      MethodChannel('ir.mhdolatabadi.nafir/local_audio');

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<LocalAudioResult> load() async {
    if (!supported) {
      return const LocalAudioResult(LocalAudioStatus.unsupported);
    }
    try {
      final raw =
          await _channel.invokeMethod<List<Object?>>('queryAudio') ?? const [];
      final tracks = raw.map((item) {
        final map = Map<Object?, Object?>.from(item! as Map);
        String? text(String key) {
          final value = map[key] as String?;
          return value == null || value == '<unknown>' || value.isEmpty
              ? null
              : value;
        }

        return Track(
          id: 'device:${map['id']}',
          title: text('title') ?? 'بدون نام',
          artist: text('artist'),
          album: text('album'),
          contentType: text('contentType') ?? 'audio/*',
          sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
          sourceUri: Uri.parse(map['uri']! as String),
        );
      }).toList(growable: false);
      return LocalAudioResult(LocalAudioStatus.loaded, tracks);
    } on PlatformException catch (error) {
      if (error.code == 'PERMISSION_DENIED') {
        return const LocalAudioResult(LocalAudioStatus.permissionDenied);
      }
      rethrow;
    }
  }
}

LocalAudioLibrary createLocalAudioLibrary() =>
    AndroidLocalAudioLibrary();
