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

    library.result =
        const LocalAudioResult(LocalAudioStatus.loaded, [track]);
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
}
