/// One timed line of synced lyrics.
class LyricLine {
  const LyricLine(this.time, this.text);

  /// When the line starts in the track.
  final Duration time;
  final String text;
}

/// The LRCLIB entry lyrics come from, so a listener can tell a wrong match.
class LyricsMatch {
  const LyricsMatch({
    required this.id,
    required this.trackName,
    required this.artistName,
    this.albumName = '',
    this.duration,
    this.synced = false,
  });

  factory LyricsMatch.fromJson(Map<String, dynamic> json) {
    final ms = (json['durationMs'] as num?)?.toInt() ?? 0;
    return LyricsMatch(
      id: (json['id'] as num).toInt(),
      trackName: json['trackName'] as String? ?? '',
      artistName: json['artistName'] as String? ?? '',
      albumName: json['albumName'] as String? ?? '',
      duration: ms > 0 ? Duration(milliseconds: ms) : null,
      synced: json['synced'] == true,
    );
  }

  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final Duration? duration;

  /// Whether the entry has timed lyrics.
  final bool synced;
}

enum LyricsStatus { found, instrumental, notFound }

/// A track's lyrics as the server found them on LRCLIB.
class TrackLyrics {
  const TrackLyrics({
    required this.status,
    this.lines = const [],
    this.plain,
    this.match,
    this.chosen = false,
    this.canChoose = false,
  });

  factory TrackLyrics.fromJson(Map<String, dynamic> json) {
    final synced = json['synced'] as String?;
    final match = json['match'] as Map<String, dynamic>?;
    return TrackLyrics(
      status: switch (json['status']) {
        'found' => LyricsStatus.found,
        'instrumental' => LyricsStatus.instrumental,
        _ => LyricsStatus.notFound,
      },
      lines: synced == null ? const [] : parseLrc(synced),
      plain: json['plain'] as String?,
      match: match == null ? null : LyricsMatch.fromJson(match),
      chosen: json['chosen'] == true,
      canChoose: json['canChoose'] == true,
    );
  }

  final LyricsStatus status;

  /// Timed lines, in order; empty when only plain lyrics exist.
  final List<LyricLine> lines;
  final String? plain;
  final LyricsMatch? match;

  /// The track's owner picked [match] by hand.
  final bool chosen;

  /// Whether this listener may pick another match: only the track's owner.
  final bool canChoose;

  bool get isSynced => lines.isNotEmpty;

  /// The plain text, or the synced lines without their times.
  String get text => plain?.trim().isNotEmpty == true
      ? plain!.trim()
      : lines.map((line) => line.text).join('\n');
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text: lines like `[01:02.34]words`, where one line may carry
/// several times. Metadata tags (`[ar:…]`) and untimed lines are skipped;
/// an empty timed line is kept as a pause.
List<LyricLine> parseLrc(String source) {
  final lines = <LyricLine>[];
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    var rest = raw.trim();
    final times = <Duration>[];
    while (true) {
      final match = _timeTag.matchAsPrefix(rest);
      if (match == null) break;
      final fraction = match.group(3) ?? '0';
      times.add(Duration(
        minutes: int.parse(match.group(1)!),
        seconds: int.parse(match.group(2)!),
        milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
      ));
      rest = rest.substring(match.end).trimLeft();
    }
    for (final time in times) {
      lines.add(LyricLine(time, rest.trim()));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

/// The index of the line playing at [position], or -1 before the first.
int activeLyricLine(List<LyricLine> lines, Duration position) {
  var low = 0, high = lines.length - 1, found = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (lines[mid].time <= position) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}
