class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.contentType,
    required this.sizeBytes,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        contentType: json['contentType'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
      );

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String contentType;
  final int sizeBytes;
}
