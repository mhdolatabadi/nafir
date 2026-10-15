import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/library/data/track.dart';
import 'package:rhythmo/features/player/application/playback_metrics.dart';
import 'package:rhythmo/features/player/application/player_controller.dart';
import 'package:rhythmo/features/player/data/audio_engine.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

const _a = Track(id: 'a', title: 'A', contentType: 'audio/mpeg', sizeBytes: 1);
const _b = Track(id: 'b', title: 'B', contentType: 'audio/mpeg', sizeBytes: 1);

void main() {
  test('time to first audio and stalls are counted per play', () {
    final metrics = PlaybackMetrics(log: false);
    final t0 = DateTime(2026, 10, 14, 12);
    metrics.started('a', t0);
    metrics.status(PlayerStatus.loading, t0);
    metrics.status(
        PlayerStatus.playing, t0.add(const Duration(milliseconds: 820)));
    // A stall, then playing again, then another stall.
    for (final second in [10, 12, 30, 31]) {
      metrics.status(
          second.isEven ? PlayerStatus.buffering : PlayerStatus.playing,
          t0.add(Duration(seconds: second)));
    }
    metrics.status(PlayerStatus.buffering, t0.add(const Duration(seconds: 40)));
    // Pausing and buffering while paused are not stalls.
    metrics.status(PlayerStatus.paused, t0.add(const Duration(seconds: 50)));

    final play = metrics.current!;
    expect(play.firstAudio, const Duration(milliseconds: 820));
    expect(play.stalls, 2);
    expect(play.toString(), 'playback: a first audio in 820 ms, 2 stalls');

    metrics.started('b', t0.add(const Duration(minutes: 3)), preloaded: true);
    expect(metrics.current!.firstAudio, Duration.zero);
    expect(metrics.plays.map((p) => p.trackId), ['a', 'b']);
  });

  test('buffering before the first audio is not a stall', () {
    final metrics = PlaybackMetrics(log: false);
    final t0 = DateTime(2026);
    metrics.started('a', t0);
    metrics.status(PlayerStatus.loading, t0);
    metrics.status(PlayerStatus.buffering, t0);
    metrics.status(PlayerStatus.playing, t0.add(const Duration(seconds: 2)));
    expect(metrics.current!.stalls, 0);
    expect(metrics.current!.firstAudio, const Duration(seconds: 2));
  });

  test('only the most recent plays are kept', () {
    final metrics = PlaybackMetrics(log: false);
    for (var i = 0; i < 60; i++) {
      metrics.started('t$i', DateTime(2026));
    }
    expect(metrics.plays.length, 50);
    expect(metrics.plays.first.trackId, 't10');
  });

  test('the player feeds the metrics from its own status', () async {
    var now = DateTime(2026, 10, 14, 12);
    final engine = FakeAudioEngine();
    final player = PlayerController(
        api: FakeTracksApi(),
        engine: engine,
        token: () => 'tok',
        now: () => now);
    addTearDown(player.dispose);

    final playing = player.playFrom(const [_a, _b], 0);
    now = now.add(const Duration(milliseconds: 640));
    await playing;
    await pumpEventQueue();
    expect(player.status, PlayerStatus.playing);
    expect(player.metrics.current!.trackId, 'a');
    expect(
        player.metrics.current!.firstAudio, const Duration(milliseconds: 640));

    engine.stateCtl.add(EngineState.buffering);
    await pumpEventQueue();
    expect(player.status, PlayerStatus.buffering);
    engine.stateCtl.add(EngineState.ready);
    await pumpEventQueue();
    expect(player.metrics.current!.stalls, 1);
  });
}
