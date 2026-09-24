import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/storage_uploader.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

/// Records the request and never answers until it is cancelled.
class HangingAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    await cancelFuture;
    throw DioException.requestCancelled(
        requestOptions: options, reason: 'cancelled');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final ticket = UploadTicket(
    track: const Track(
        id: 't1', title: 'Song', contentType: 'audio/mpeg', sizeBytes: 4),
    url: Uri.parse('https://music.example.com/nafir-music/'),
    fields: const {'key': 'users/u1/tracks/t1/song.mp3', 'policy': 'p'},
  );

  test('cancelling stops the request with UploadCancelled', () async {
    final adapter = HangingAdapter();
    final cancel = Completer<void>();
    final upload =
        DioStorageUploader(Dio()..httpClientAdapter = adapter).upload(
      ticket,
      PickedAudio(
        name: 'song.mp3',
        sizeBytes: 4,
        openRead: () => Stream.value([1, 2, 3, 4]),
      ),
      contentType: 'audio/mpeg',
      onProgress: (_, __) {},
      cancelled: cancel.future,
    );
    await pumpEventQueue();
    expect(adapter.request?.uri.toString(),
        'https://music.example.com/nafir-music/');

    cancel.complete();

    await expectLater(upload, throwsA(isA<UploadCancelled>()));
  });
}
