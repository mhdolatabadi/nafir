import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

import 'local_audio_upload_stub.dart'
    if (dart.library.io) 'local_audio_upload_io.dart' as platform;

abstract interface class LocalAudioUploadSource {
  Future<PickedAudio> prepare(Track track);
}

LocalAudioUploadSource createLocalAudioUploadSource() =>
    platform.createLocalAudioUploadSource();
