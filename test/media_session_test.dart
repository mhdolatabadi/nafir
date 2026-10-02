import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/media_session.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/audio_engine.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

final _artwork = Uri.file('/data/nafir_notification_artwork.png');

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
    handler = NafirAudioHandler(artwork: _artwork)..attach(player);
  });

  test('the system shows the current track and its duration', () async {
    await player.playFrom(_tracks, 0);

    final item = handler.mediaItem.value!;
    expect(item.id, 'a');
    expect(item.title, 'First');
    expect(item.artist, 'Artist');
    expect(item.album, 'Album');
    expect(item.duration, const Duration(minutes: 3));
    expect(item.artUri, _artwork);
    expect(item.displayTitle, 'First');
    expect(item.displaySubtitle, 'Artist');
    expect(item.displayDescription, 'پخش از کتابخانهٔ نفیر');
    expect(item.extras?['location'], 'server');
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
    expect(handler.mediaItem.value?.artist, 'روی سرور');
    expect(handler.mediaItem.value?.displaySubtitle, 'روی سرور');

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

  test('titles are cleaned and fall back to the filename', () {
    String title(String value, {String? fileName}) =>
        NafirAudioHandler.notificationTitle(Track(
            id: 'x',
            title: value,
            fileName: fileName,
            contentType: 'audio/mpeg',
            sizeBytes: 1));

    expect(title('  سلام\n  Hello  '), 'سلام Hello');
    expect(title(' ', fileName: 'My Song.final.mp3'), 'My Song.final');
    expect(title('', fileName: '.mp3'), '.mp3');
    expect(title(''), untitledTrack);
  });

  test('a track without artist or album shows where it plays from', () async {
    const local = Track(
        id: 'l',
        title: 'Local',
        artist: '  ',
        album: '',
        contentType: 'audio/mpeg',
        sizeBytes: 1);
    await player.playFrom([local], 0);

    final item = handler.mediaItem.value!;
    expect(item.artist, 'روی سرور');
    expect(item.album, 'نفیر');
    expect(item.artUri, _artwork, reason: 'the Nafir logo is the fallback');
  });

  test(
      'without resolved artwork the item has no image rather than a '
      'URI the system cannot load', () async {
    final bare = NafirAudioHandler()..attach(player);
    await player.playFrom(_tracks, 0);
    expect(bare.mediaItem.value?.artUri, isNull);
  });

  test('loading, buffering, completed and error map to system states',
      () async {
    final states = <AudioProcessingState>[];
    final subscription = handler.playbackState
        .map((state) => state.processingState)
        .distinct()
        .listen(states.add);

    await player.playFrom(_tracks, 1);
    engine.stateCtl.add(EngineState.buffering);
    engine.stateCtl.add(EngineState.ready);
    engine.playingCtl.add(false);
    engine.stateCtl.add(EngineState.completed);
    await pumpEventQueue();
    expect(player.status, PlayerStatus.completed);
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls[1], MediaControl.play);

    engine.loadError = Exception('unreachable');
    await player.playFrom(_tracks, 0);
    await pumpEventQueue();
    await subscription.cancel();

    expect(states, [
      AudioProcessingState.idle,
      AudioProcessingState.loading,
      AudioProcessingState.ready,
      AudioProcessingState.buffering,
      AudioProcessingState.ready,
      AudioProcessingState.completed,
      AudioProcessingState.loading,
      AudioProcessingState.error,
    ]);
    expect(handler.playbackState.value.errorMessage, isNotEmpty);
  });

  test('the item is published once per track, not on every tick', () async {
    final items = <MediaItem?>[];
    final subscription = handler.mediaItem.skip(1).listen(items.add);

    await player.playFrom(_tracks, 0);
    for (var s = 1; s <= 5; s++) {
      engine.positionCtl.add(Duration(seconds: s));
    }
    engine.playingCtl.add(false);
    engine.playingCtl.add(true);
    await pumpEventQueue();
    await subscription.cancel();

    // Once for the new track, once when its duration became known.
    expect(items.map((item) => item?.duration), [
      null,
      const Duration(minutes: 3),
    ]);
  });
}
