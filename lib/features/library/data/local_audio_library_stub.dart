import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/track.dart';

class UnsupportedLocalAudioLibrary implements LocalAudioLibrary {
  @override
  bool get supported => false;

  @override
  Future<LocalAudioResult> load() async =>
      const LocalAudioResult(LocalAudioStatus.unsupported);

  @override
  Future<bool> delete(Track track) =>
      throw UnsupportedError('There is no device music here.');
}

LocalAudioLibrary createLocalAudioLibrary() => UnsupportedLocalAudioLibrary();
