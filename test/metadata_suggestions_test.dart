import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/library/application/metadata_suggestions.dart';
import 'package:rhythmo/features/library/data/track.dart';

Track _t(String id, {String? artist, String? album, String? albumArtist}) =>
    Track(
      id: id,
      title: id,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      contentType: 'audio/mpeg',
      sizeBytes: 1,
    );

void main() {
  test('collects distinct values, most used first, in the common spelling', () {
    final s = MetadataSuggestions.fromTracks([
      _t('1', artist: 'حسین طاهری'),
      _t('2', artist: 'محمود كريمي'), // Arabic ك and ي
      _t('3', artist: 'محمود کریمی'),
      _t('4', artist: 'محمود کریمی ', albumArtist: 'حسین طاهری'),
      _t('5', artist: '  ', album: 'ای ایران'),
      _t('6', artist: 'حسین طاهری'),
    ]);
    expect(s.artists, ['حسین طاهری', 'محمود کریمی']);
    expect(s.albums, ['ای ایران']);
    expect(s.genres, isEmpty);
  });

  test('matches prefixes first, then contained text, across spellings', () {
    const ranked = ['علی رضایی', 'رضا صادقی', 'Reza Sadeghi', 'محمدرضا'];
    // A word starting with the query counts as a prefix match.
    expect(
        matchSuggestions(ranked, 'رضا'), ['علی رضایی', 'رضا صادقی', 'محمدرضا']);
    expect(matchSuggestions(ranked, 'صادق'), ['رضا صادقی']);
    expect(matchSuggestions(ranked, 'reza'), ['Reza Sadeghi']);
    expect(matchSuggestions(['محمود کریمی'], 'كريم'), ['محمود کریمی']);
  });

  test('suggests nothing for an empty query or an exact value', () {
    expect(matchSuggestions(['آلبوم'], ''), isEmpty);
    expect(matchSuggestions(['آلبوم'], 'آلبوم'), isEmpty);
  });

  test('stops at the limit', () {
    final ranked = [for (var i = 0; i < 20; i++) 'خواننده $i'];
    expect(matchSuggestions(ranked, 'خوا', limit: 4), hasLength(4));
  });
}
