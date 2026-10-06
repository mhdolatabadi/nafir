import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track_download.dart';
import 'package:nafir/features/library/data/track_download_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every HTTP request with 400; this test talks
  // to a real server on the loopback interface.
  setUpAll(() => HttpOverrides.global = null);
  const channel = MethodChannel(AndroidTrackDownloader.channelName);
  late HttpServer server;
  late Directory work;
  late List<Map<Object?, Object?>> saves;
  late List<int> savedBytes;
  Object? saveError;

  /// What the server sends: [body], declared as [length] bytes, optionally
  /// stalling after the first half until [release] completes.
  late List<int> body;
  int? declaredLength;
  Completer<void>? release;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('downloads');
    saves = [];
    savedBytes = [];
    saveError = null;
    body = List.generate(1000, (i) => i % 256);
    declaredLength = null;
    release = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response..bufferOutput = false;
      response.headers.contentLength = declaredLength ?? body.length;
      response.headers.set('content-type', 'audio/mpeg');
      response.add(body.sublist(0, body.length ~/ 2));
      await response.flush();
      final gate = release;
      if (gate != null) await gate.future;
      try {
        response.add(body.sublist(body.length ~/ 2));
        await response.close();
      } catch (_) {}
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveAudio');
      final args = call.arguments as Map<Object?, Object?>;
      saves.add(args);
      savedBytes = await File(args['path']! as String).readAsBytes();
      if (saveError != null) throw saveError!;
      return 'content://media/external/audio/media/9';
    });
  });

  tearDown(() async {
    await server.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await work.delete(recursive: true);
  });

  AndroidTrackDownloader downloader() =>
      AndroidTrackDownloader(android: true, workDirectory: () async => work);

  DownloadLink link() => DownloadLink(
        Uri.parse('http://${server.address.host}:${server.port}/song.mp3'),
        DateTime.now().add(const Duration(hours: 1)),
        'My_Song.mp3',
      );

  Future<void> download(
    AndroidTrackDownloader d, {
    int? size,
    List<(int, int)>? progress,
    Future<void>? cancelled,
  }) =>
      d.download(
        link(),
        contentType: 'audio/mpeg',
        sizeBytes: size ?? body.length,
        onProgress: (r, t) => progress?.add((r, t)),
        cancelled: cancelled ?? Completer<void>().future,
      );

  test('saves the exact bytes under the filename and cleans up', () async {
    final progress = <(int, int)>[];

    await download(downloader(), progress: progress);

    expect(saves.single['fileName'], 'My_Song.mp3');
    expect(saves.single['mimeType'], 'audio/mpeg');
    expect(savedBytes, body);
    expect(progress.last, (1000, 1000));
    expect(work.listSync(), isEmpty);
  });

  test('a short file is never saved and the part file is removed', () async {
    await expectLater(
      download(downloader(), size: 2000),
      throwsA(isA<DownloadException>()
          .having((e) => e.reason, 'reason', DownloadFailure.incomplete)),
    );
    expect(saves, isEmpty);
    expect(work.listSync(), isEmpty);
  });

  test('cancelling stops the transfer and removes the part file', () async {
    release = Completer<void>();
    final cancel = Completer<void>();
    final progress = <(int, int)>[];
    final running =
        download(downloader(), progress: progress, cancelled: cancel.future);
    for (var i = 0; i < 100 && progress.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    cancel.complete();
    await expectLater(running, throwsA(isA<DownloadCancelled>()));
    release!.complete();
    expect(saves, isEmpty);
    expect(work.listSync(), isEmpty);
  });

  test('an unreachable server is reported as offline', () async {
    final unreachable = link();
    await server.close(force: true);

    await expectLater(
      downloader().download(
        unreachable,
        contentType: 'audio/mpeg',
        sizeBytes: body.length,
        onProgress: (_, __) {},
        cancelled: Completer<void>().future,
      ),
      throwsA(isA<DownloadException>()
          .having((e) => e.reason, 'reason', DownloadFailure.offline)),
    );
    expect(work.listSync(), isEmpty);
  });

  test('Android errors are explained: duplicate, permission, space', () async {
    for (final (code, reason) in const [
      ('DUPLICATE', DownloadFailure.duplicate),
      ('PERMISSION_DENIED', DownloadFailure.permission),
      ('NO_SPACE', DownloadFailure.storageFull),
      ('SAVE_FAILED', DownloadFailure.unknown),
    ]) {
      saveError = PlatformException(code: code);
      await expectLater(
        download(downloader()),
        throwsA(
            isA<DownloadException>().having((e) => e.reason, 'reason', reason)),
      );
      expect(work.listSync(), isEmpty);
    }
  });

  test('only Android saves to the device', () async {
    final other = AndroidTrackDownloader(android: false);
    expect(other.savesToDevice, isFalse);
    await expectLater(
      download(other),
      throwsA(isA<DownloadException>()
          .having((e) => e.reason, 'reason', DownloadFailure.unsupported)),
    );
  });
}
