import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/data/loudness.dart';

Track _track(ReplayGain? replayGain) => Track(
    id: 't',
    title: 't',
    contentType: 'audio/mpeg',
    sizeBytes: 1,
    replayGain: replayGain);

void main() {
  test('a loud track is turned down to the reference level', () {
    // -6.02 dB is half the amplitude.
    final gain = normalizationGain(
        _track(const ReplayGain(trackGainDb: -6.0206)), LoudnessMode.track);
    expect(gain, closeTo(0.5, 1e-4));
  });

  test('the peak caps the gain so normalizing never clips', () {
    // -1 dB would be 0.891, but a 1.5 peak allows only 0.667.
    final gain = normalizationGain(
        _track(const ReplayGain(trackGainDb: -1, trackPeak: 1.5)),
        LoudnessMode.track);
    expect(gain, closeTo(1 / 1.5, 1e-9));
    expect(gain * 1.5, lessThanOrEqualTo(1));
  });

  test('a quiet track is never pushed past full scale', () {
    expect(
        normalizationGain(
            _track(const ReplayGain(trackGainDb: 4, trackPeak: 0.5)),
            LoudnessMode.track),
        1);
  });

  test('album mode uses album values and falls back to the track', () {
    const both = ReplayGain(
        trackGainDb: -9, trackPeak: 0.9, albumGainDb: -6.0206, albumPeak: 0.9);
    expect(normalizationGain(_track(both), LoudnessMode.album),
        closeTo(0.5, 1e-4));
    expect(normalizationGain(_track(both), LoudnessMode.track),
        closeTo(0.3548, 1e-4));
    const trackOnly = ReplayGain(trackGainDb: -6.0206);
    expect(normalizationGain(_track(trackOnly), LoudnessMode.album),
        closeTo(0.5, 1e-4));
    // An album gain without its own peak still respects the track's peak.
    const albumNoPeak = ReplayGain(albumGainDb: 0, trackPeak: 1.25);
    expect(normalizationGain(_track(albumNoPeak), LoudnessMode.album),
        closeTo(0.8, 1e-9));
  });

  test('off, or no ReplayGain, plays the file as stored', () {
    const loud = ReplayGain(trackGainDb: -10);
    expect(normalizationGain(_track(loud), LoudnessMode.off), 1);
    expect(normalizationGain(_track(null), LoudnessMode.track), 1);
    expect(
        normalizationGain(
            _track(const ReplayGain(trackPeak: 0.5)), LoudnessMode.track),
        1);
  });

  test('the track JSON is read, and missing fields stay unknown', () {
    final track = Track.fromJson({
      'id': 't1',
      'title': 't',
      'fileName': 't.mp3',
      'contentType': 'audio/mpeg',
      'sizeBytes': 10,
      'createdAt': '2026-01-01T00:00:00Z',
      'replayGain': {
        'trackGainDb': -7.25,
        'trackPeak': 0.98,
        'albumGainDb': null,
        'albumPeak': null
      },
    });
    expect(track.replayGain?.trackGainDb, -7.25);
    expect(track.replayGain?.trackPeak, 0.98);
    expect(track.replayGain?.albumGainDb, isNull);
    final plain = Track.fromJson({
      'id': 't2',
      'title': 't',
      'fileName': 't.mp3',
      'contentType': 'audio/mpeg',
      'sizeBytes': 10,
      'createdAt': '2026-01-01T00:00:00Z',
      'replayGain': null,
    });
    expect(plain.replayGain, isNull);
  });
}
