import 'package:nafir/core/api/api_client.dart';

import 'track_download_stub.dart'
    if (dart.library.io) 'track_download_io.dart'
    if (dart.library.js_interop) 'track_download_web.dart' as platform;

/// Why a download failed, for a short Persian explanation.
enum DownloadFailure {
  offline,
  storageFull,
  permission,

  /// Fewer bytes arrived than the track has; nothing was saved.
  incomplete,

  /// The same file is already in the device's music.
  duplicate,
  unsupported,
  unknown,
}

class DownloadException implements Exception {
  const DownloadException(this.reason);

  final DownloadFailure reason;

  @override
  String toString() => 'Download failed: $reason';
}

/// Thrown when a download stops because the user cancelled it.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Saves a track's original file, byte for byte.
abstract interface class TrackDownloader {
  /// True when downloads land in this device's music, with progress, and
  /// play offline (Android); false when the browser saves the file (web).
  bool get savesToDevice;

  /// Downloads [link]. Reports progress while it can, stops when
  /// [cancelled] completes (throwing [DownloadCancelled]), and leaves no
  /// partial file behind on failure.
  Future<void> download(
    DownloadLink link, {
    required String contentType,
    required int sizeBytes,
    required void Function(int received, int total) onProgress,
    required Future<void> cancelled,
  });
}

TrackDownloader createTrackDownloader() => platform.createTrackDownloader();
