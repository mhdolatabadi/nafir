import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

abstract interface class LocalAudioUploadSource {
  Future<PickedAudio> prepare(Track track);
}
