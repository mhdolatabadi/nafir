import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nafir/features/library/data/local_audio_upload_base.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

class MethodChannelLocalAudioUploadSource implements LocalAudioUploadSource {
  static const _channel = MethodChannel('ir.mhdolatabadi.nafir/local_audio');

  @override
  Future<PickedAudio> prepare(Track track) async {
    final uri = track.sourceUri;
    if (uri == null) {
      throw ArgumentError.value(track.id, 'track', 'Track is not local.');
    }

    final name = _uploadName(track);
    final path = await _channel.invokeMethod<String>('copyAudioToCache', {
      'uri': uri.toString(),
      'fileName': name,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Local audio file could not be prepared.');
    }

    final file = File(path);
    return PickedAudio(
      name: name,
      sizeBytes: await file.length(),
      openRead: file.openRead,
      release: () async {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      },
    );
  }

  static String _uploadName(Track track) {
    final fileName = track.fileName?.trim();
    if (fileName != null && fileName.isNotEmpty) return fileName;

    final extension = switch (track.contentType) {
      'audio/mpeg' => '.mp3',
      'audio/mp4' || 'audio/aac' => '.m4a',
      'audio/flac' => '.flac',
      'audio/ogg' => '.ogg',
      'audio/wav' || 'audio/x-wav' => '.wav',
      _ => '.audio',
    };
    final title = track.title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    return '${title.isEmpty ? 'track' : title}$extension';
  }
}

LocalAudioUploadSource createLocalAudioUploadSource() =>
    MethodChannelLocalAudioUploadSource();
