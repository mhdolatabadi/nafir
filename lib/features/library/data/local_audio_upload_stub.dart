import 'package:rhythmo/features/library/data/local_audio_upload_base.dart';
import 'package:rhythmo/features/library/data/track.dart';
import 'package:rhythmo/features/upload/data/upload_models.dart';

class UnsupportedLocalAudioUploadSource implements LocalAudioUploadSource {
  @override
  Future<PickedAudio> prepare(Track track) {
    throw UnsupportedError('Local audio upload is not supported here.');
  }
}

LocalAudioUploadSource createLocalAudioUploadSource() =>
    UnsupportedLocalAudioUploadSource();
