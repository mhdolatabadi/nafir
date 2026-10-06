import 'package:nafir/features/library/data/track.dart';

/// The editable metadata of a cloud track, as typed in the editor. Text is
/// kept as typed; empty optional values clear the field on save.
class TrackMetadataDraft {
  const TrackMetadataDraft({
    required this.fileName,
    required this.title,
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.composer = '',
    this.genre = '',
    this.comment = '',
    this.year,
    this.trackNumber,
    this.discNumber,
  });

  factory TrackMetadataDraft.fromTrack(Track track) => TrackMetadataDraft(
        fileName: track.fileName ?? '',
        title: track.title,
        artist: track.artist ?? '',
        album: track.album ?? '',
        albumArtist: track.albumArtist ?? '',
        composer: track.composer ?? '',
        genre: track.genre ?? '',
        comment: track.comment ?? '',
        year: track.year,
        trackNumber: track.trackNumber,
        discNumber: track.discNumber,
      );

  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String composer;
  final String genre;
  final String comment;
  final int? year;
  final int? trackNumber;
  final int? discNumber;

  /// Whether saving this would change nothing, ignoring surrounding spaces.
  bool sameAs(TrackMetadataDraft other) =>
      fileName.trim() == other.fileName.trim() &&
      title.trim() == other.title.trim() &&
      artist.trim() == other.artist.trim() &&
      album.trim() == other.album.trim() &&
      albumArtist.trim() == other.albumArtist.trim() &&
      composer.trim() == other.composer.trim() &&
      genre.trim() == other.genre.trim() &&
      comment.trim() == other.comment.trim() &&
      year == other.year &&
      trackNumber == other.trackNumber &&
      discNumber == other.discNumber;
}

/// What happened to a metadata save.
sealed class MetadataSaveResult {
  const MetadataSaveResult();
}

class MetadataSaved extends MetadataSaveResult {
  const MetadataSaved(this.track);
  final Track track;
}

/// Someone changed the track since the editor opened; [latest] is the
/// server's copy. Nothing was written.
class MetadataConflict extends MetadataSaveResult {
  const MetadataConflict(this.latest);
  final Track latest;
}

/// The server rejected [field] (named as in the API, e.g. `fileName`).
class MetadataInvalid extends MetadataSaveResult {
  const MetadataInvalid(this.field);
  final String field;
}

class MetadataSaveFailed extends MetadataSaveResult {
  const MetadataSaveFailed();
}
