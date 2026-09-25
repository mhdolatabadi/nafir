import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:nafir/features/player/application/player_controller.dart';

/// Connects the system's media controls (notification, lock screen, headset
/// buttons and, on the web, the browser's MediaSession) to [PlayerController].
class NafirAudioHandler extends BaseAudioHandler with SeekHandler {
  PlayerController? _player;
  String? _mediaId;
  Duration? _mediaDuration;
  PlaybackState? _last;

  /// Drives [player] from the system controls and mirrors its state back.
  void attach(PlayerController player) {
    _player?.removeListener(_sync);
    _player = player;
    player.addListener(_sync);
    _sync();
  }

  @override
  Future<void> play() async => _player?.resume();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> skipToNext() async => _player?.next();

  @override
  Future<void> skipToPrevious() async => _player?.previous();

  @override
  Future<void> stop() async {
    await _player?.stop();
    await super.stop();
  }

  void _sync() {
    final player = _player;
    if (player == null) return;
    final track = player.track;

    if (track?.id != _mediaId || player.duration != _mediaDuration) {
      _mediaId = track?.id;
      _mediaDuration = player.duration;
      mediaItem.add(track == null
          ? null
          : MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album,
              duration: player.duration,
            ));
    }

    final playing = player.status == PlayerStatus.playing ||
        player.status == PlayerStatus.buffering;
    final next = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (player.status) {
        PlayerStatus.idle => AudioProcessingState.idle,
        PlayerStatus.loading => AudioProcessingState.loading,
        PlayerStatus.buffering => AudioProcessingState.buffering,
        PlayerStatus.playing ||
        PlayerStatus.paused =>
          AudioProcessingState.ready,
        PlayerStatus.completed => AudioProcessingState.completed,
        PlayerStatus.error => AudioProcessingState.error,
      },
      playing: playing,
      updatePosition: player.position,
    );
    // Position ticks many times a second; the system extrapolates it from
    // updatePosition, so only publish real changes and seeks.
    if (_last != null && !_changed(_last!, next)) return;
    _last = next;
    playbackState.add(next);
  }

  static bool _changed(PlaybackState before, PlaybackState after) {
    if (before.playing != after.playing ||
        before.processingState != after.processingState) {
      return true;
    }
    final drift = (after.updatePosition - before.position).inMilliseconds.abs();
    return drift > 1500;
  }
}

/// The running media session, if [startMediaSession] succeeded.
NafirAudioHandler? activeMediaSession;

/// Starts the platform media session. Returns null where it cannot run (for
/// example in tests), in which case the app simply has no system controls.
Future<NafirAudioHandler?> startMediaSession() async {
  try {
    final session = await AudioSession.instance;
    // Music: pause for calls and other apps' audio, duck for notifications.
    await session.configure(const AudioSessionConfiguration.music());
    return activeMediaSession = await AudioService.init(
      builder: NafirAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'ir.mhdolatabadi.nafir.playback',
        androidNotificationChannelName: 'پخش موسیقی',
        androidNotificationIcon: 'drawable/ic_stat_nafir',
        androidNotificationOngoing: true,
      ),
    );
  } catch (error) {
    debugPrint('Media session unavailable: $error');
    return null;
  }
}
