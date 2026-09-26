import 'package:nafir/features/library/data/local_audio_library.dart';

class UnsupportedLocalAudioLibrary implements LocalAudioLibrary {
  @override
  bool get supported => false;

  @override
  Future<LocalAudioResult> load() async =>
      const LocalAudioResult(LocalAudioStatus.unsupported);
}

LocalAudioLibrary createLocalAudioLibrary() => UnsupportedLocalAudioLibrary();
