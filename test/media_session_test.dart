import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/media_session.dart';
import 'package:nafir/features/player/application/player_controller.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

const _tracks = [
  Track(
      id: 'a',
      title: 'First',
      artist: 'Artist',
      album: 'Album',
      contentType: 'audio/mpeg',
      sizeBytes: 1),
  Track(id: 'b', title: 'Second', contentType: 'audio/mpeg', sizeBytes: 1),
];

void main() {
  late FakeAudioEngine engine;
  late PlayerController player;
  late NafirAudioHandler handler;

  setUp(() {
    engine = FakeAudioEngine();
    player = PlayerController(
        api: FakeTracksApi(), engine: engine, token: () => 'tok');
    handler = NafirAudioHandler()..attach(player);
  });

  test('the system shows the current track and its duration', () async {
    await player.playFrom(_tracks, 0);

    final item = handler.mediaItem.value!;
    expect(item.id, 'a');
    expect(item.title, 'First');
    expect(item.artist, 'Artist');
    expect(item.album, 'Album');
    expect(item.duration, const Duration(minutes: 3));
  });

  test('playback state mirrors the player with prev/pause/next controls',
      () async {
    await player.playFrom(_tracks, 0);

    var state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
    ]);
    expect(state.systemActions, contains(MediaAction.seek));

    await player.pause();
    state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.controls[1], MediaControl.play);
  });

  test('lock-screen buttons drive the player', () async {
    await player.playFrom(_tracks, 0);

    await handler.pause();
    expect(player.status, PlayerStatus.paused);
    await handler.play();
    expect(player.status, PlayerStatus.playing);

    await handler.skipToNext();
    expect(player.track?.id, 'b');
    expect(handler.mediaItem.value?.title, 'Second');

    await handler.skipToPrevious();
    expect(player.track?.id, 'a');

    await handler.seek(const Duration(seconds: 42));
    expect(engine.calls, contains('seek:42'));
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 42));
  });

  test('ordinary position ticks do not flood the system with updates',
      () async {
    await player.playFrom(_tracks, 0);
    final updates = <PlaybackState>[];
    final subscription = handler.playbackState.skip(1).listen(updates.add);

    for (var ms = 200; ms <= 1000; ms += 200) {
      engine.positionCtl.add(Duration(milliseconds: ms));
    }
    await pumpEventQueue();

    expect(updates, isEmpty);
    await subscription.cancel();
  });

  test('stop from the system clears the track', () async {
    await player.playFrom(_tracks, 0);
    await handler.stop();
    expect(player.track, isNull);
    expect(handler.mediaItem.value, isNull);
  });
}
