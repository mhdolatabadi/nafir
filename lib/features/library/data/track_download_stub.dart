import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track_download.dart';

class UnsupportedTrackDownloader implements TrackDownloader {
  @override
  bool get savesToDevice => false;

  @override
  Future<void> download(
    DownloadLink link, {
    required String contentType,
    required int sizeBytes,
    required void Function(int received, int total) onProgress,
    required Future<void> cancelled,
  }) =>
      throw const DownloadException(DownloadFailure.unsupported);
}

TrackDownloader createTrackDownloader() => UnsupportedTrackDownloader();
