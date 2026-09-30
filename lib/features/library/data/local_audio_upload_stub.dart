import 'package:nafir/features/library/data/local_audio_upload.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

class UnsupportedLocalAudioUploadSource implements LocalAudioUploadSource {
  @override
  Future<PickedAudio> prepare(Track track) {
    throw UnsupportedError('Local audio upload is not supported here.');
  }
}

LocalAudioUploadSource createLocalAudioUploadSource() =>
    UnsupportedLocalAudioUploadSource();
