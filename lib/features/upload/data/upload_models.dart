import 'package:nafir/features/library/data/track.dart';

/// A pending track and the presigned form that uploads its file to storage.
class UploadTicket {
  const UploadTicket({
    required this.track,
    required this.url,
    required this.fields,
  });

  factory UploadTicket.fromJson(Map<String, dynamic> json) {
    final upload = json['upload'] as Map<String, dynamic>;
    return UploadTicket(
      track: Track.fromJson(json['track'] as Map<String, dynamic>),
      url: Uri.parse(upload['url'] as String),
      fields: (upload['fields'] as Map<String, dynamic>).cast<String, String>(),
    );
  }

  final Track track;
  final Uri url;
  final Map<String, String> fields;
}

/// An audio file the user picked. [openRead] streams it without keeping a
/// second copy; [release] drops any temporary copy the platform made.
class PickedAudio {
  const PickedAudio({
    required this.name,
    required this.sizeBytes,
    required this.openRead,
    this.release,
  });

  final String name;
  final int sizeBytes;
  final Stream<List<int>> Function() openRead;
  final Future<void> Function()? release;
}
