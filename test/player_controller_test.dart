import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/audio_engine.dart';

import 'upload_controller_test.dart' show FakeTracksApi;

/// Records calls and lets tests drive the engine's streams.
class FakeAudioEngine implements AudioEngine {
  final positionCtl = StreamController<Duration>.broadcast(sync: true);
  final durationCtl = StreamController<Duration?>.broadcast(sync: true);
  final playingCtl = StreamController<bool>.broadcast(sync: true);
  final stateCtl = StreamController<EngineState>.broadcast(sync: true);
  final errorCtl = StreamController<Object>.broadcast(sync: true);
  final loads = <(String, Uri, Duration)>[];
  final calls = <String>[];
  Object? loadError;

  @override
  Stream<Duration> get position => positionCtl.stream;
  @override
  Stream<Duration?> get duration => durationCtl.stream;
  @override
  Stream<bool> get playing => playingCtl.stream;
  @override
  Stream<EngineState> get state => stateCtl.stream;
  @override
  Stream<Object> get errors => errorCtl.stream;

  @override
  Future<void> load(Track track, Uri url,
      {Duration start = Duration.zero}) async {
    loads.add((track.id, url, start));
    if (loadError != null) throw loadError!;
    stateCtl.add(EngineState.ready);
    durationCtl.add(const Duration(minutes: 3));
  }

  @override
  void play() {
    calls.add('play');
    playingCtl.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playingCtl.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    positionCtl.add(position);
    // Like just_audio, seeking leaves the completed state.
    stateCtl.add(EngineState.ready);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    playingCtl.add(false);
    stateCtl.add(EngineState.idle);
  }

  @override
  Future<void> dispose() async {}
}

const _a = Track(id: 'a', title: 'A', contentType: 'audio/mpeg', sizeBytes: 1);
const _b = Track(id: 'b', title: 'B', contentType: 'audio/mpeg', sizeBytes: 1);

void main() {
  late FakeTracksApi api;
  late FakeAudioEngine engine;
  late PlayerController player;

  setUp(() {
    api = FakeTracksApi();
    engine = FakeAudioEngine();
    player = PlayerController(api: api, engine: engine, token: () => 'tok');
  });

  test('plays a track from a fresh stream link', () async {
    final seen = <PlayerStatus>[];
    player.addListener(() => seen.add(player.status));

    await player.play(_a);

    expect(seen.first, PlayerStatus.loading);
    expect(player.status, PlayerStatus.playing);
    expect(player.track?.id, 'a');
    expect(player.duration, const Duration(minutes: 3));
    expect(engine.loads.single.$2.path, '/nafir-music/a');
  });

  test('tapping the current track pauses and resumes it', () async {
    await player.play(_a);

    await player.play(_a);
    expect(player.status, PlayerStatus.paused);
    await player.play(_a);
    expect(player.status, PlayerStatus.playing);
    expect(engine.loads, hasLength(1), reason: 'no reload for the same track');
  });

  test('buffering while playing is reported', () async {
    await player.play(_a);
    engine.stateCtl.add(EngineState.buffering);
    expect(player.status, PlayerStatus.buffering);
    engine.stateCtl.add(EngineState.ready);
    expect(player.status, PlayerStatus.playing);
  });

  test('seek moves the engine and the reported position', () async {
    await player.play(_a);
    await player.seek(const Duration(seconds: 42));
    expect(engine.calls, contains('seek:42'));
    expect(player.position, const Duration(seconds: 42));
  });

  test('a failed link or load is an error that retry recovers', () async {
    api.linkError = Exception('offline');
    await player.play(_a);
    expect(player.status, PlayerStatus.error);

    api.linkError = null;
    await player.toggle();
    expect(player.status, PlayerStatus.playing);
  });

  test('an expired URL is replaced once and playback resumes in place',
      () async {
    await player.play(_a);
    engine.positionCtl.add(const Duration(seconds: 90));

    engine.errorCtl.add(Exception('403'));
    await pumpEventQueue();

    expect(engine.loads, hasLength(2));
    expect(engine.loads.last.$3, const Duration(seconds: 90));
    expect(engine.loads.last.$2, isNot(engine.loads.first.$2));
    expect(player.status, PlayerStatus.playing);

    engine.errorCtl.add(Exception('403 again'));
    await pumpEventQueue();
    expect(player.status, PlayerStatus.error);
    expect(engine.loads, hasLength(2), reason: 'only one automatic retry');
  });

  test('switching tracks while one is loading keeps the newest', () async {
    final first = player.play(_a);
    final second = player.play(_b);
    await Future.wait([first, second]);
    expect(player.track?.id, 'b');
    expect(player.status, PlayerStatus.playing);
  });

  test('completion, then play restarts from the beginning', () async {
    await player.play(_a);
    engine.playingCtl.add(false);
    engine.stateCtl.add(EngineState.completed);
    expect(player.status, PlayerStatus.completed);

    await player.toggle();
    expect(engine.calls, contains('seek:0'));
    expect(player.status, PlayerStatus.playing);
  });

  test('stop forgets the track', () async {
    await player.play(_a);
    await player.stop();
    expect(player.track, isNull);
    expect(player.status, PlayerStatus.idle);
  });

  test('without a session nothing is requested', () async {
    final signedOut =
        PlayerController(api: api, engine: engine, token: () => null);
    await signedOut.play(_a);
    expect(api.calls, isEmpty);
    expect(signedOut.track, isNull);
  });
}
