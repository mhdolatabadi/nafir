import 'package:rhythmo/features/library/data/track.dart';
import 'package:rhythmo/features/upload/data/upload_models.dart';

abstract interface class LocalAudioUploadSource {
  Future<PickedAudio> prepare(Track track);
}
