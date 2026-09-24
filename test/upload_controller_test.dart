import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/storage_uploader.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

const _pendingTrack = Track(
  id: 't1',
  title: 'Song',
  contentType: 'audio/mpeg',
  sizeBytes: 4,
);

class FakeTracksApi implements TracksApi {
  FakeTracksApi([List<Track>? tracks]) : tracks = [...?tracks];

  /// What the server lists; a completed upload is added to it.
  final List<Track> tracks;
  Object? listError;
  Completer<void>? createGate;
  Object? createError;
  Object? completeError;
  final deleted = <String>[];
  final calls = <String>[];

  @override
  Future<List<Track>> listTracks(String token) async {
    calls.add('list');
    if (listError != null) throw listError!;
    return List.of(tracks);
  }

  @override
  Future<UploadTicket> createUpload(
      String token, String fileName, int sizeBytes) async {
    calls.add('create:$token:$fileName:$sizeBytes');
    await createGate?.future;
    if (createError != null) throw createError!;
    return UploadTicket(
      track: _pendingTrack,
      url: Uri.parse('https://music.example.com/nafir-music/'),
      fields: const {'key': 'users/u1/tracks/t1/song.mp3'},
    );
  }

  @override
  Future<Track> completeUpload(String token, String trackId) async {
    calls.add('complete:$trackId');
    if (completeError != null) throw completeError!;
    tracks.insert(0, _pendingTrack);
    return _pendingTrack;
  }

  @override
  Future<void> deleteTrack(String token, String trackId) async {
    deleted.add(trackId);
  }
}

class FakeUploader implements StorageUploader {
  Object? error;
  String? contentType;

  /// When set, the upload stalls halfway until it is cancelled.
  bool stall = false;

  @override
  Future<void> upload(
    UploadTicket ticket,
    PickedAudio file, {
    required String contentType,
    required void Function(int sent, int total) onProgress,
    required Future<void> cancelled,
  }) async {
    this.contentType = contentType;
    onProgress(2, 4);
    if (stall) {
      await cancelled;
      throw const UploadCancelled();
    }
    if (error != null) throw error!;
    onProgress(4, 4);
  }
}

PickedAudio _file(String name, {int size = 4, void Function()? onRelease}) =>
    PickedAudio(
      name: name,
      sizeBytes: size,
      openRead: () => Stream.value([1, 2, 3, 4]),
      release: () async => onRelease?.call(),
    );

void main() {
  late FakeTracksApi api;
  late FakeUploader uploader;
  late UploadController controller;
  late List<(UploadPhase, double)> seen;

  setUp(() {
    api = FakeTracksApi();
    uploader = FakeUploader();
    controller = UploadController(
      api: api,
      uploader: uploader,
      token: () => 'tok',
    );
    seen = [];
    controller
        .addListener(() => seen.add((controller.phase, controller.progress)));
  });

  test('uploads, reports progress and verifies', () async {
    var released = false;
    await controller
        .upload(_file('song.MP3', onRelease: () => released = true));

    expect(controller.phase, UploadPhase.done);
    expect(controller.uploaded?.title, 'Song');
    expect(uploader.contentType, 'audio/mpeg');
    expect(api.calls, ['create:tok:song.MP3:4', 'complete:t1']);
    expect(seen.map((s) => s.$1).toSet(), {
      UploadPhase.preparing,
      UploadPhase.uploading,
      UploadPhase.verifying,
      UploadPhase.done,
    });
    expect(seen, contains((UploadPhase.uploading, 0.5)));
    expect(released, isTrue,
        reason: 'the temporary picker copy must be released');
    expect(api.deleted, isEmpty);
  });

  test('rejects unsupported, empty and oversized files without calling the API',
      () async {
    for (final (file, error) in [
      (_file('notes.txt'), UploadError.unsupportedFormat),
      (_file('empty.mp3', size: 0), UploadError.emptyFile),
      (_file('huge.mp3', size: 300 * 1024 * 1024), UploadError.tooLarge),
    ]) {
      await controller.upload(file);
      expect(controller.phase, UploadPhase.failed);
      expect(controller.error, error);
    }
    expect(api.calls, isEmpty);
  });

  test('a failed storage upload removes the pending track', () async {
    uploader.error = const UploadFailed(403);
    var released = false;

    await controller
        .upload(_file('song.mp3', onRelease: () => released = true));

    expect(controller.error, UploadError.network);
    expect(api.deleted, ['t1']);
    expect(released, isTrue);
  });

  test('a file the server rejects is reported and not deleted twice', () async {
    api.completeError =
        const ApiException('422', statusCode: 422, code: 'invalid_audio');

    await controller.upload(_file('song.mp3'));

    expect(controller.error, UploadError.invalidAudio);
    expect(api.deleted, isEmpty);
  });

  test('a rejected reservation is reported without cleanup', () async {
    api.createError =
        const ApiException('413', statusCode: 413, code: 'invalid_size');

    await controller.upload(_file('song.mp3'));

    expect(controller.error, UploadError.tooLarge);
    expect(api.deleted, isEmpty);
  });

  test('dismiss returns to idle after a result', () async {
    await controller.upload(_file('song.mp3'));
    controller.dismiss();
    expect(controller.phase, UploadPhase.idle);
  });

  test('cancelling mid-upload removes the pending track and goes idle',
      () async {
    uploader.stall = true;
    final done = controller.upload(_file('song.mp3'));
    await pumpEventQueue();
    expect(controller.phase, UploadPhase.uploading);
    expect(controller.canCancel, isTrue);

    controller.cancel();
    await done;

    expect(controller.phase, UploadPhase.idle);
    expect(controller.error, isNull);
    expect(api.deleted, ['t1']);
    expect(api.calls, isNot(contains('complete:t1')));
  });

  test('cancelling while the track is being reserved uploads nothing',
      () async {
    api.createGate = Completer();
    final done = controller.upload(_file('song.mp3'));
    await pumpEventQueue();
    expect(controller.phase, UploadPhase.preparing);

    controller.cancel();
    api.createGate!.complete();
    await done;

    expect(controller.phase, UploadPhase.idle);
    expect(uploader.contentType, isNull, reason: 'no bytes should be sent');
    expect(api.deleted, ['t1']);
  });

  test('reading state ends when the picker is closed without a file', () {
    controller.readingFile();
    expect(controller.phase, UploadPhase.reading);
    expect(controller.canCancel, isFalse);
    controller.pickCancelled();
    expect(controller.phase, UploadPhase.idle);
  });

  test('a picked file is uploaded after the reading state', () async {
    controller.readingFile();
    await controller.upload(_file('song.mp3'));
    expect(controller.phase, UploadPhase.done);
  });
}
