class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.contentType,
    required this.sizeBytes,
    this.sourceUri,
    this.source,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        contentType: json['contentType'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        source: json['source'] as String?,
      );

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String contentType;
  final int sizeBytes;

  /// Present only for audio discovered on this device (usually content://).
  final Uri? sourceUri;

  bool get isLocal => sourceUri != null;

  /// Where a cloud track came from: `upload`, or the bot that imported it
  /// (`bale`, `telegram`).
  final String? source;

  /// The messenger a bot imported this track from, for people; null for
  /// tracks uploaded in the app.
  String? get importedFrom => switch (source) {
        'bale' => 'بله',
        'telegram' => 'تلگرام',
        _ => null,
      };
}
