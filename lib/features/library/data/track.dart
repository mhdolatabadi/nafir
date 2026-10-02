class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.composer,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.comment,
    required this.contentType,
    required this.sizeBytes,
    this.fileName,
    this.sourceUri,
    this.source,
    this.sharedVia,
    this.addedBy,
    this.viaPlaylist,
  });

  /// [viaPlaylist] is the collaborative playlist a track someone else added
  /// was listed in; it is then played through that playlist.
  factory Track.fromJson(Map<String, dynamic> json,
          {String? sharedVia, String? viaPlaylist}) =>
      Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        albumArtist: json['albumArtist'] as String?,
        composer: json['composer'] as String?,
        genre: json['genre'] as String?,
        year: (json['year'] as num?)?.toInt(),
        trackNumber: (json['trackNumber'] as num?)?.toInt(),
        discNumber: (json['discNumber'] as num?)?.toInt(),
        comment: json['comment'] as String?,
        contentType: json['contentType'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        fileName: json['fileName'] as String?,
        source: json['source'] as String?,
        sharedVia: sharedVia,
        addedBy: json['addedBy'] as String?,
        viaPlaylist: json['addedBy'] == null ? null : viaPlaylist,
      );

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? composer;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String? comment;
  final String contentType;
  final int sizeBytes;

  /// Original filename when the platform exposes it. Local uploads use this
  /// to preserve the extension for format detection.
  final String? fileName;

  /// Present only for audio discovered on this device (usually content://).
  final Uri? sourceUri;

  bool get isLocal => sourceUri != null;

  /// Where a cloud track came from: `upload`, or the bot that imported it
  /// (`bale`, `telegram`).
  final String? source;

  /// The share token of the playlist this track was opened from, when it is
  /// someone else's track; it is then played through that link.
  final String? sharedVia;

  /// In a collaborative playlist, who added this track when it isn't the
  /// viewer's own (their email, masked); null for the viewer's own tracks.
  final String? addedBy;

  /// The playlist someone else's track is played through, see [addedBy].
  final String? viaPlaylist;

  /// The messenger a bot imported this track from, for people; null for
  /// tracks uploaded in the app.
  String? get importedFrom => switch (source) {
        'bale' => 'بله',
        'telegram' => 'تلگرام',
        _ => null,
      };
}
