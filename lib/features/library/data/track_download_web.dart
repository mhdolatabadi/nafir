import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track_download.dart';
import 'package:web/web.dart' as web;

/// Hands the download to the browser: the link's storage response says
/// Content-Disposition: attachment, so the browser saves the original file
/// under its name with its own progress and cancel, and the page stays.
class BrowserTrackDownloader implements TrackDownloader {
  @override
  bool get savesToDevice => false;

  @override
  Future<void> download(
    DownloadLink link, {
    required String contentType,
    required int sizeBytes,
    required void Function(int received, int total) onProgress,
    required Future<void> cancelled,
  }) async {
    final anchor = web.HTMLAnchorElement()
      ..href = link.url.toString()
      ..download = link.fileName
      ..rel = 'noopener';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
}

TrackDownloader createTrackDownloader() => BrowserTrackDownloader();
