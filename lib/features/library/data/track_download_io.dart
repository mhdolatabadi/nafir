import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track_download.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads into the app's cache as a `.part` file, checks that every byte
/// arrived, then asks Android to add it to the device's music (Music/rhythmo)
/// where local discovery finds it, so it plays offline. The partial file is
/// always deleted, whether the download completed, failed or was cancelled.
class AndroidTrackDownloader implements TrackDownloader {
  AndroidTrackDownloader({
    Dio? dio,
    bool? android,
    Future<Directory> Function()? workDirectory,
    MethodChannel? channel,
  })  : _dio = dio ?? Dio(),
        _android = android ?? Platform.isAndroid,
        _workDirectory = workDirectory ?? _defaultWorkDirectory,
        _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'ir.mhdolatabadi.nafir/local_audio';

  final Dio _dio;
  final bool _android;
  final Future<Directory> Function() _workDirectory;
  final MethodChannel _channel;

  static Future<Directory> _defaultWorkDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/nafir_downloads');

  @override
  bool get savesToDevice => _android;

  @override
  Future<void> download(
    DownloadLink link, {
    required String contentType,
    required int sizeBytes,
    required void Function(int received, int total) onProgress,
    required Future<void> cancelled,
  }) async {
    if (!_android) throw const DownloadException(DownloadFailure.unsupported);
    final directory = await _workDirectory();
    await directory.create(recursive: true);
    final part = File('${directory.path}/'
        '${DateTime.now().microsecondsSinceEpoch}.part');
    final cancelToken = CancelToken();
    var stopped = false;
    unawaited(cancelled.then((_) {
      stopped = true;
      cancelToken.cancel();
    }));
    try {
      try {
        await _dio.downloadUri(
          link.url,
          part.path,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) =>
              onProgress(received, total > 0 ? total : sizeBytes),
          options: Options(
            // The bytes as stored; never decoded or re-encoded on the way.
            headers: {HttpHeaders.acceptEncodingHeader: 'identity'},
          ),
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) throw const DownloadCancelled();
        throw DownloadException(_dioFailure(error));
      } on FileSystemException catch (error) {
        throw DownloadException(_fileFailure(error));
      }
      if (stopped) throw const DownloadCancelled();
      if (sizeBytes > 0 && await part.length() != sizeBytes) {
        throw const DownloadException(DownloadFailure.incomplete);
      }
      try {
        await _channel.invokeMethod<String>('saveAudio', {
          'path': part.path,
          'fileName': link.fileName,
          'mimeType': contentType,
        });
      } on PlatformException catch (error) {
        throw DownloadException(switch (error.code) {
          'DUPLICATE' => DownloadFailure.duplicate,
          'PERMISSION_DENIED' => DownloadFailure.permission,
          'NO_SPACE' => DownloadFailure.storageFull,
          _ => DownloadFailure.unknown,
        });
      }
    } finally {
      try {
        if (await part.exists()) await part.delete();
      } on FileSystemException {
        // The cache is cleared by the OS eventually.
      }
    }
  }

  static DownloadFailure _dioFailure(DioException error) {
    if (error.error case final FileSystemException fileError) {
      return _fileFailure(fileError);
    }
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        DownloadFailure.offline,
      DioExceptionType.unknown when error.error is SocketException =>
        DownloadFailure.offline,
      _ => DownloadFailure.unknown,
    };
  }

  /// ENOSPC is 28 on Linux, and so on Android.
  static DownloadFailure _fileFailure(FileSystemException error) =>
      error.osError?.errorCode == 28
          ? DownloadFailure.storageFull
          : DownloadFailure.unknown;
}

TrackDownloader createTrackDownloader() => AndroidTrackDownloader();
