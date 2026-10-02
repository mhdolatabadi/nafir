import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/application/library_sync_controller.dart';
import 'package:nafir/features/library/data/local_audio_upload.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

import 'upload_controller_test.dart' show FakeTracksApi, FakeUploader;

/// Copies device tracks "into the cache"; [error] makes it fail.
class FakeUploadSource implements LocalAudioUploadSource {
  Object? error;
  Completer<void>? gate;
  final prepared = <String>[];
  final released = <String>[];

  @override
  Future<PickedAudio> prepare(Track track) async {
    await gate?.future;
    if (error != null) throw error!;
    prepared.add(track.id);
    return PickedAudio(
      name: track.fileName ?? 'song.mp3',
      sizeBytes: track.sizeBytes,
      openRead: () => Stream.value(List.filled(track.sizeBytes, 0)),
      release: () async => released.add(track.id),
    );
  }
}

Track device(int id, {String fileName = 'song.mp3'}) => Track(
      id: 'device:$id',
      title: 'Device $id',
      contentType: 'audio/mpeg',
      sizeBytes: 4,
      fileName: fileName,
      sourceUri: Uri.parse('content://media/external/audio/media/$id'),
    );

void main() {
  late FakeTracksApi api;
  late FakeUploader uploader;
  late FakeUploadSource source;
  late UploadController uploads;
  late LibrarySyncController sync;
  late int refreshed;
  late List<SyncOperation> finished;

  setUp(() {
    api = FakeTracksApi();
    uploader = FakeUploader();
    source = FakeUploadSource();
    uploads =
        UploadController(api: api, uploader: uploader, token: () => 'token');
    refreshed = 0;
    sync = LibrarySyncController(
      uploads: uploads,
      uploadSource: source,
      onUploaded: () async => refreshed++,
    );
    finished = [];
    sync.finished.listen(finished.add);
  });

  Future<void> settle() => pumpEventQueue();

  test('uploads a device track and forgets it once the list shows it',
      () async {
    final track = device(1);
    final seen = <(SyncPhase, double)?>[];
    sync.addListener(() {
      final op = sync.operationFor(track.id);
      seen.add(op == null ? null : (op.phase, op.progress));
    });

    sync.upload(track);
    expect(sync.operationFor(track.id)?.phase, isNotNull);
    await settle();

    expect(source.prepared, [track.id]);
    expect(source.released, [track.id]);
    expect(api.calls, contains('create:token:song.mp3:4'));
    expect(refreshed, 1);
    expect(sync.operationFor(track.id), isNull);
    expect(
        seen,
        containsAllInOrder([
          (SyncPhase.queued, 0.0),
          (SyncPhase.running, 0.0),
          (SyncPhase.running, 0.5),
          (SyncPhase.running, 1.0),
          null,
        ]));
    expect(finished.single.error, isNull);
  });

  test('a full quota fails with a reason, and retrying succeeds', () async {
    final track = device(1);
    api.createError =
        const ApiException('quota', statusCode: 413, code: 'quota_exceeded');

    sync.upload(track);
    await settle();

    final failed = sync.operationFor(track.id)!;
    expect(failed.phase, SyncPhase.failed);
    expect(failed.error, SyncError.quota);
    expect(finished.single.error, SyncError.quota);
    expect(syncErrorMessage(SyncError.quota), contains('فضای ابری'));
    expect(refreshed, 0);

    api.createError = null;
    sync.retry(track.id);
    await settle();

    expect(sync.operationFor(track.id), isNull);
    expect(refreshed, 1);
  });

  test('a lost connection is reported as offline', () async {
    api.createError = Exception('SocketException: Failed host lookup');

    sync.upload(device(1));
    await settle();

    expect(sync.operationFor('device:1')!.error, SyncError.offline);
  });

  test('denied media access is reported as a permission problem', () async {
    source.error = PlatformException(code: 'PERMISSION_DENIED');

    sync.upload(device(1));
    await settle();

    expect(sync.operationFor('device:1')!.error, SyncError.permission);
    expect(uploads.isBusy, isFalse);
  });

  test('uploads run one at a time; a queued one can be cancelled', () async {
    source.gate = Completer<void>();
    sync.upload(device(1));
    sync.upload(device(2));
    sync.upload(device(3));
    await settle();

    expect(sync.operationFor('device:1')!.phase, SyncPhase.running);
    expect(sync.operationFor('device:2')!.phase, SyncPhase.queued);
    expect(sync.canCancel('device:2'), isTrue);

    sync.cancel('device:2');
    expect(sync.operationFor('device:2'), isNull);

    source.gate!.complete();
    await settle();

    expect(source.prepared, ['device:1', 'device:3']);
    expect(sync.operations, isEmpty);
    expect(refreshed, 2);
  });

  test('a running upload can be cancelled and leaves nothing behind', () async {
    uploader.stall = true;
    sync.upload(device(1));
    await settle();

    expect(sync.operationFor('device:1')!.progress, 0.5);
    expect(sync.canCancel('device:1'), isTrue);
    sync.cancel('device:1');
    await settle();

    expect(sync.operationFor('device:1'), isNull);
    expect(api.deleted, ['t1']);
    expect(finished, isEmpty);
    expect(refreshed, 0);
  });

  test('waits for a picked file that is still uploading', () async {
    uploader.stall = true;
    unawaited(uploads.upload(PickedAudio(
      name: 'picked.mp3',
      sizeBytes: 4,
      openRead: () => Stream.value([1, 2, 3, 4]),
    )));
    await settle();

    sync.upload(device(1));
    await settle();
    expect(sync.operationFor('device:1')!.phase, SyncPhase.queued);

    uploader.stall = false;
    uploads.cancel();
    await settle();

    expect(source.prepared, ['device:1']);
    expect(sync.operations, isEmpty);
  });

  test('a failed upload can be dismissed; clear forgets everything', () async {
    api.createError = const ApiException('x', statusCode: 500, code: 'x');
    sync.upload(device(1));
    await settle();

    sync.dismiss('device:1');
    expect(sync.operationFor('device:1'), isNull);

    sync.upload(device(2));
    sync.clear();
    await settle();
    expect(sync.operations, isEmpty);
  });
}
