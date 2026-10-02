import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/track.dart';

class FakeLocalAudioLibrary implements LocalAudioLibrary {
  FakeLocalAudioLibrary(this.result, {this.supported = true});

  LocalAudioResult result;
  @override
  final bool supported;

  @override
  Future<LocalAudioResult> load() async => result;

  /// What deleting answers: true, false (declined) or an error to throw.
  Object deleteAnswer = true;
  final deleted = <Uri>[];

  @override
  Future<bool> delete(Track track) async {
    final answer = deleteAnswer;
    if (answer is! bool) throw answer;
    if (answer) {
      deleted.add(track.sourceUri!);
      result = LocalAudioResult(result.status, [
        for (final t in result.tracks)
          if (t.sourceUri != track.sourceUri) t,
      ]);
    }
    return answer;
  }
}

void main() {
  const track = Track(
    id: 'device:1',
    title: 'Local',
    contentType: 'audio/mpeg',
    sizeBytes: 10,
  );

  test('loads device tracks', () async {
    final controller = LocalAudioController(FakeLocalAudioLibrary(
      const LocalAudioResult(LocalAudioStatus.loaded, [track]),
    ));

    await controller.load();

    expect(controller.status, LocalAudioViewStatus.loaded);
    expect(controller.tracks, [track]);
  });

  test('reports denied permission and supports retry', () async {
    final library = FakeLocalAudioLibrary(
      const LocalAudioResult(LocalAudioStatus.permissionDenied),
    );
    final controller = LocalAudioController(library);

    await controller.load();
    expect(controller.status, LocalAudioViewStatus.permissionDenied);

    library.result = const LocalAudioResult(LocalAudioStatus.loaded, [track]);
    await controller.load();
    expect(controller.status, LocalAudioViewStatus.loaded);
    expect(controller.tracks, [track]);
  });

  test('unsupported platforms do not query', () async {
    final controller = LocalAudioController(FakeLocalAudioLibrary(
      const LocalAudioResult(LocalAudioStatus.loaded, [track]),
      supported: false,
    ));

    await controller.load();

    expect(controller.status, LocalAudioViewStatus.unsupported);
    expect(controller.tracks, isEmpty);
  });

  group('deleting a device track', () {
    final local = Track(
      id: 'device:7',
      title: 'Local',
      contentType: 'audio/mpeg',
      sizeBytes: 10,
      sourceUri: Uri.parse('content://media/external/audio/media/7'),
    );

    Future<(FakeLocalAudioLibrary, LocalAudioController)> loaded() async {
      final library = FakeLocalAudioLibrary(
          LocalAudioResult(LocalAudioStatus.loaded, [local]));
      final controller = LocalAudioController(library);
      await controller.load();
      return (library, controller);
    }

    test('removes it from the list once deleted', () async {
      final (library, controller) = await loaded();

      expect(await controller.delete(local), DeviceDeleteResult.deleted);
      expect(library.deleted, [local.sourceUri]);
      expect(controller.tracks, isEmpty);
    });

    test('a synced track is deleted by its device file', () async {
      final (library, controller) = await loaded();
      const cloud = Track(
          id: 't1', title: 'Local', contentType: 'audio/mpeg', sizeBytes: 10);

      expect(await controller.delete(cloud.withDeviceCopy(local.sourceUri!)),
          DeviceDeleteResult.deleted);
      expect(library.deleted, [local.sourceUri]);
      expect(controller.tracks, isEmpty);
    });

    test('keeps it when the user declines or access is denied', () async {
      final (library, controller) = await loaded();

      library.deleteAnswer = false;
      expect(await controller.delete(local), DeviceDeleteResult.declined);
      library.deleteAnswer = PlatformException(code: 'PERMISSION_DENIED');
      expect(
          await controller.delete(local), DeviceDeleteResult.permissionDenied);
      library.deleteAnswer = PlatformException(code: 'DELETE_FAILED');
      expect(await controller.delete(local), DeviceDeleteResult.failed);
      expect(controller.tracks, [local]);
    });
  });
}
