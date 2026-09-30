export 'local_audio_upload_base.dart';

import 'local_audio_upload_base.dart';
import 'local_audio_upload_stub.dart'
    if (dart.library.io) 'local_audio_upload_io.dart' as platform;

LocalAudioUploadSource createLocalAudioUploadSource() =>
    platform.createLocalAudioUploadSource();
