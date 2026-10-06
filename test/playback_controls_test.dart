import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/playback_settings.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/audio_engine.dart';
import 'package:nafir/features/player/data/crossfade.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

const _a = Track(id: 'a', title: 'A', contentType: 'audio/mpeg', sizeBytes: 1);
const _b = Track(id: 'b', title: 'B', contentType: 'audio/mpeg', sizeBytes: 1);
const _c = Track(id: 'c', title: 'C', contentType: 'audio/mpeg', sizeBytes: 1);
const _abc = [_a, _b, _c];

/// The fake engine reports every track as three minutes long.
const _length = Duration(minutes: 3);

void main() {
  late FakeTracksApi api;
  late FakeAudioEngine engine;
  late MemoryPlaybackSettingsStore store;

  setUp(() {
    api = FakeTracksApi();
    engine = FakeAudioEngine();
    store = MemoryPlaybackSettingsStore();
  });

  PlayerController controller({DateTime Function()? now}) => PlayerController(
        api: api,
        engine: engine,
        token: () => 'tok',
        settingsStore: store,
        now: now,
      );

  /// Runs [body] in fake time, with the player's clock following it.
  void inFakeTime(
      void Function(FakeAsync async, PlayerController player) body) {
    fakeAsync((async) {
      final start = DateTime(2026, 10, 6, 23);
      final player = controller(now: () => start.add(async.elapsed));
      body(async, player);
      player.dispose();
    });
  }

  group('sleep timer', () {
    test('counts down, fades out over the last seconds, then pauses', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 15));
        expect(player.sleepTimerActive, isTrue);
        expect(player.sleepRemaining, const Duration(minutes: 15));

        async.elapse(const Duration(minutes: 10));
        expect(player.sleepRemaining, const Duration(minutes: 5));
        expect(player.status, PlayerStatus.playing);
        expect(engine.volumes, isEmpty, reason: 'no fade yet');

        async.elapse(const Duration(minutes: 4, seconds: 57));
        expect(player.sleepFading, isTrue);
        expect(engine.volumes, isNotEmpty);
        expect(engine.volumes.last, inExclusiveRange(0, 1));
        expect(player.status, PlayerStatus.playing);

        async.elapse(const Duration(seconds: 4));
        expect(player.status, PlayerStatus.paused);
        expect(engine.calls.last, 'pause');
        expect(engine.volumes.last, 1, reason: 'volume is back for next time');
        expect(player.sleepTimerActive, isFalse);
        expect(player.sleepRemaining, isNull);
      });
    });

    test('the fade only ever lowers the volume', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 15));
        async.elapse(
            const Duration(minutes: 14, seconds: 59, milliseconds: 900));
        final fade = List.of(engine.volumes);
        expect(fade, isNotEmpty);
        for (var i = 1; i < fade.length; i++) {
          expect(fade[i], lessThanOrEqualTo(fade[i - 1]));
        }
      });
    });

    test('cancelling during the fade restores the volume and keeps playing',
        () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 29, seconds: 57));
        expect(player.sleepFading, isTrue);

        player.cancelSleepTimer();
        async.elapse(const Duration(seconds: 10));
        expect(player.sleepTimerActive, isFalse);
        expect(engine.volumes.last, 1);
        expect(player.status, PlayerStatus.playing);
        expect(engine.calls, isNot(contains('pause')));
      });
    });

    test('pressing play while it fades out cancels the timer', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 45));
        async.elapse(const Duration(minutes: 44, seconds: 57));
        // A headset button pauses, then the listener plays again.
        player.pause();
        async.flushMicrotasks();
        player.resume();
        async.elapse(const Duration(seconds: 10));
        expect(player.sleepTimerActive, isFalse);
        expect(engine.volumes.last, 1);
        expect(player.status, PlayerStatus.playing);
      });
    });

    test('a timer that runs out while paused just ends', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 60));
        player.pause();
        async.elapse(const Duration(minutes: 61));
        expect(player.sleepTimerActive, isFalse);
        expect(engine.volumes, isEmpty);
        expect(player.status, PlayerStatus.paused);
      });
    });

    test('a new timer replaces the old one', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 5));
        player.setSleepTimer(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 20));
        expect(player.status, PlayerStatus.playing);
        expect(player.sleepRemaining, const Duration(minutes: 10));
      });
    });

    test('at the end of the track it fades, stops and readies the next one',
        () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        engine.positionCtl.add(const Duration(minutes: 2, seconds: 40));
        async.flushMicrotasks();
        expect(engine.preloaded, 'b');

        player.setSleepAtTrackEnd();
        async.flushMicrotasks();
        expect(player.sleepsAtTrackEnd, isTrue);
        expect(engine.preloaded, isNull,
            reason: 'the track must end instead of moving on gaplessly');

        engine.positionCtl.add(_length - const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 4));
        expect(engine.volumes.last, 0);

        engine.playingCtl.add(false);
        engine.stateCtl.add(EngineState.completed);
        async.flushMicrotasks();
        expect(player.track?.id, 'b', reason: 'play again continues here');
        expect(player.status, PlayerStatus.paused);
        expect(engine.calls.where((call) => call == 'play'), hasLength(1));
        expect(engine.volumes.last, 1);
        expect(player.sleepTimerActive, isFalse);
      });
    });

    test('stopping playback clears the timer', () {
      inFakeTime((async, player) {
        player.playFrom(_abc, 0);
        async.flushMicrotasks();
        player.setSleepTimer(const Duration(minutes: 15));
        player.stop();
        async.flushMicrotasks();
        expect(player.sleepTimerActive, isFalse);
      });
    });
  });

  group('speed', () {
    test('changes the engine rate and is remembered', () async {
      final player = controller();
      await player.setSpeed(1.5);
      expect(player.speed, 1.5);
      expect(engine.speed, 1.5);
      expect(store.settings.speed, 1.5);
      player.dispose();

      engine = FakeAudioEngine();
      final next = controller();
      await next.loadSettings();
      expect(next.speed, 1.5);
      expect(engine.speed, 1.5);
      next.dispose();
    });

    test('stays within the offered range', () async {
      final player = controller();
      await player.setSpeed(5);
      expect(player.speed, 2);
      await player.setSpeed(0.1);
      expect(player.speed, 0.75);
      player.dispose();
    });

    test('a speed chosen before the saved one loads wins', () async {
      store.settings = const PlaybackSettings(speed: 2);
      final player = controller();
      await player.setSpeed(1.25);
      await player.loadSettings();
      expect(player.speed, 1.25);
      player.dispose();
    });
  });

  group('crossfade', () {
    test('is off by default, set on the engine and remembered', () async {
      final player = controller();
      expect(player.crossfade, Duration.zero);
      await player.setCrossfade(const Duration(seconds: 4));
      expect(engine.crossfade, const Duration(seconds: 4));
      expect(store.settings.crossfade, const Duration(seconds: 4));
      player.dispose();

      engine = FakeAudioEngine();
      final next = controller();
      await next.loadSettings();
      expect(next.crossfade, const Duration(seconds: 4));
      expect(engine.crossfade, const Duration(seconds: 4));
      next.dispose();
    });

    test('is capped at eight seconds', () async {
      final player = controller();
      await player.setCrossfade(const Duration(seconds: 20));
      expect(player.crossfade, maxCrossfade);
      player.dispose();
    });

    test('is ignored where the platform cannot overlap tracks', () async {
      engine.crossfadeSupported = false;
      store.settings = const PlaybackSettings(crossfade: Duration(seconds: 6));
      final player = controller();
      expect(player.supportsCrossfade, isFalse);
      await player.loadSettings();
      expect(player.crossfade, Duration.zero);
      await player.setCrossfade(const Duration(seconds: 3));
      expect(player.crossfade, Duration.zero);
      expect(engine.crossfade, Duration.zero);
      player.dispose();
    });

    test('preloads early enough for the overlap', () async {
      final player = controller();
      await player.setCrossfade(const Duration(seconds: 8));
      await player.playFrom(_abc, 0);
      engine.positionCtl
          .add(_length - preloadLead - const Duration(seconds: 9));
      await pumpEventQueue();
      expect(engine.preloaded, isNull);
      engine.positionCtl
          .add(_length - preloadLead - const Duration(seconds: 7));
      await pumpEventQueue();
      expect(engine.preloaded, 'b');
      player.dispose();
    });

    test('changing it re-buffers the next track for the new overlap', () async {
      final player = controller();
      await player.playFrom(_abc, 0);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 45));
      await pumpEventQueue();
      expect(engine.preloads, ['b']);
      await player.setCrossfade(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(engine.preloads, ['b', null, 'b']);
      player.dispose();
    });
  });

  group('gapless', () {
    test('the next track is buffered near the end and played without loading',
        () async {
      final player = controller();
      await player.playFrom(_abc, 0);
      engine.positionCtl.add(const Duration(minutes: 1));
      await pumpEventQueue();
      expect(engine.preloaded, isNull, reason: 'too early: links expire');

      engine.positionCtl.add(const Duration(minutes: 2, seconds: 31));
      await pumpEventQueue();
      expect(engine.preloaded, 'b');
      expect(api.calls, ['stream:a', 'stream:b']);

      engine.advance();
      await pumpEventQueue();
      expect(player.track?.id, 'b');
      expect(player.status, PlayerStatus.playing);
      expect(player.duration, const Duration(minutes: 4));
      expect(player.upcoming.map((t) => t.id), ['c']);
      expect([for (final load in engine.loads) load.$1], ['a'],
          reason: 'the engine already had it');

      // And the one after follows the same way.
      engine.positionCtl.add(const Duration(minutes: 3, seconds: 45));
      await pumpEventQueue();
      expect(engine.preloaded, 'c');
      player.dispose();
    });

    test('nothing is buffered at the end of the queue or on repeat-one',
        () async {
      final player = controller();
      await player.playFrom(_abc, 2);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 50));
      await pumpEventQueue();
      expect(engine.preloads, isEmpty);

      player
        ..cycleRepeat()
        ..cycleRepeat();
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 51));
      await pumpEventQueue();
      expect(engine.preloads, isEmpty);
      player.dispose();
    });

    test('a queue change drops a buffered track that no longer comes next',
        () async {
      final player = controller();
      await player.playFrom(_abc, 0);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 45));
      await pumpEventQueue();
      expect(engine.preloaded, 'b');

      await player.removeTrack('b');
      await pumpEventQueue();
      expect(engine.preloads, ['b', null, 'c']);

      // A late report of the dropped track is ignored.
      engine.advancedCtl.add('b');
      expect(player.track?.id, 'a');
      player.dispose();
    });

    test('turning repeat on at the last track buffers the first again',
        () async {
      final player = controller();
      await player.playFrom(_abc, 2);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 45));
      await pumpEventQueue();
      expect(engine.preloaded, isNull);
      player.cycleRepeat();
      await pumpEventQueue();
      expect(engine.preloaded, 'a');
      player.dispose();
    });

    test('when the engine did not move on, the fetched link is reused',
        () async {
      final player = controller();
      await player.playFrom(_abc, 0);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 45));
      await pumpEventQueue();
      final links = api.links;

      engine.stateCtl.add(EngineState.completed);
      await pumpEventQueue();
      expect(player.track?.id, 'b');
      expect(api.links, links, reason: 'no second link for b');
      expect(engine.loads.last.$1, 'b');
      player.dispose();
    });

    test('a playlist queue buffers through the playlist link', () async {
      final player = controller();
      const fromPlaylist = [
        Track(
            id: 'p1',
            title: 'P1',
            contentType: 'audio/mpeg',
            sizeBytes: 1,
            viaPlaylist: 'pl'),
        Track(
            id: 'p2',
            title: 'P2',
            contentType: 'audio/mpeg',
            sizeBytes: 1,
            viaPlaylist: 'pl'),
      ];
      await player.playFrom(fromPlaylist, 0);
      engine.positionCtl.add(const Duration(minutes: 2, seconds: 45));
      await pumpEventQueue();
      expect(engine.preloaded, 'p2');
      expect(api.calls.last, 'playlist:pl:p2');
      engine.advance();
      expect(player.track?.id, 'p2');
      player.dispose();
    });
  });

  group('settings', () {
    test('unknown saved values fall back to the defaults', () {
      final settings =
          PlaybackSettings.fromJson({'speed': 3.3, 'crossfadeMs': 'x'});
      expect(settings.speed, 1);
      expect(settings.crossfade, Duration.zero);
      expect(PlaybackSettings.fromJson(null).speed, 1);
      expect(
        PlaybackSettings.fromJson({'crossfadeMs': 60000}).crossfade,
        maxCrossfade,
      );
    });

    test('round-trip through JSON', () {
      const settings =
          PlaybackSettings(speed: 1.75, crossfade: Duration(seconds: 3));
      final read = PlaybackSettings.fromJson(settings.toJson());
      expect(read.speed, 1.75);
      expect(read.crossfade, const Duration(seconds: 3));
    });
  });

  group('crossfade timing', () {
    test('starts once the remaining time is within the overlap', () {
      const duration = Duration(minutes: 3);
      bool startsAt(Duration position, {double speed = 1}) =>
          shouldStartCrossfade(
            position: position,
            duration: duration,
            crossfade: const Duration(seconds: 4),
            speed: speed,
          );
      expect(startsAt(const Duration(minutes: 2, seconds: 55)), isFalse);
      expect(startsAt(const Duration(minutes: 2, seconds: 56)), isTrue);
      // At double speed four seconds of listening is eight of the track.
      expect(
          startsAt(const Duration(minutes: 2, seconds: 52), speed: 2), isTrue);
      expect(
        shouldStartCrossfade(
          position: duration,
          duration: duration,
          crossfade: Duration.zero,
        ),
        isFalse,
      );
    });

    test('short tracks get a shorter overlap', () {
      expect(
        effectiveCrossfade(
            const Duration(seconds: 8), const Duration(minutes: 3)),
        const Duration(seconds: 8),
      );
      expect(
        effectiveCrossfade(
            const Duration(seconds: 8), const Duration(seconds: 12)),
        const Duration(seconds: 4),
      );
      expect(
        effectiveCrossfade(
            const Duration(seconds: 8), const Duration(seconds: 12),
            speed: 2),
        const Duration(seconds: 2),
      );
      expect(effectiveCrossfade(Duration.zero, const Duration(minutes: 3)),
          Duration.zero);
    });

    test('the overlap keeps a steady loudness', () {
      for (var i = 0; i <= 10; i++) {
        final (out, into) = crossfadeGains(i / 10);
        expect(out * out + into * into, closeTo(1, 1e-9));
      }
      expect(crossfadeGains(0), (1.0, 0.0));
      final (end, start) = crossfadeGains(1);
      expect(end, closeTo(0, 1e-9));
      expect(start, 1);
    });
  });
}
