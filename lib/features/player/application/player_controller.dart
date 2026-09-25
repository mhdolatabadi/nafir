import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/play_queue.dart';
import 'package:nafir/features/player/data/audio_engine.dart';

enum PlayerStatus {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  error
}

/// "Previous" restarts the current track once it has played this long.
const restartThreshold = Duration(seconds: 3);

/// Plays a queue of tracks, one at a time, from short-lived stream URLs.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required TracksApi api,
    required AudioEngine engine,
    required String? Function() token,
    Random? random,
  })  : _api = api,
        _engine = engine,
        _token = token,
        _random = random ?? Random() {
    _subscriptions = [
      engine.position.listen((value) {
        _position = value;
        notifyListeners();
      }),
      engine.duration.listen((value) {
        _duration = value;
        notifyListeners();
      }),
      engine.playing.listen((value) {
        _playing = value;
        _refreshStatus();
      }),
      engine.state.listen((value) {
        _engineState = value;
        _refreshStatus();
      }),
      engine.errors.listen(_onEngineError),
    ];
  }

  final TracksApi _api;
  final AudioEngine _engine;
  final String? Function() _token;
  final Random _random;
  late final List<StreamSubscription<Object?>> _subscriptions;

  PlayQueue? _queue;
  bool _shuffle = false;
  QueueRepeat _repeat = QueueRepeat.off;
  bool _advancing = false;
  Track? _track;
  PlayerStatus _status = PlayerStatus.idle;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  EngineState _engineState = EngineState.idle;
  bool _loading = false;
  bool _retriedLink = false;
  int _request = 0;

  Track? get track => _track;
  bool get shuffle => _shuffle;
  QueueRepeat get repeat => _repeat;
  PlayerStatus get status => _status;
  Duration get position => _position;
  Duration? get duration => _duration;

  /// Plays [tracks] starting at [index], or toggles pause when that track
  /// is already the current one. Shuffle and repeat settings carry over.
  Future<void> playFrom(List<Track> tracks, int index) async {
    final track = tracks[index];
    if (_track?.id == track.id && _status != PlayerStatus.error) {
      return toggle();
    }
    _queue = PlayQueue(tracks, start: index, random: _random)
      ..repeat = _repeat
      ..shuffled = _shuffle;
    await _start(_queue!.current);
  }

  /// Plays a single track.
  Future<void> play(Track track) => playFrom([track], 0);

  Future<void> next() async {
    final next = _queue?.next();
    if (next != null) await _start(next);
  }

  /// Restarts the current track after its first seconds, otherwise goes back.
  Future<void> previous() async {
    final queue = _queue;
    if (queue == null) return;
    if (_position > restartThreshold) return seek(Duration.zero);
    await _start(queue.previous());
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _queue?.shuffled = _shuffle;
    notifyListeners();
  }

  /// Off → all → one → off.
  void cycleRepeat() {
    _repeat =
        QueueRepeat.values[(_repeat.index + 1) % QueueRepeat.values.length];
    _queue?.repeat = _repeat;
    notifyListeners();
  }

  Future<void> _start(Track track) async {
    final token = _token();
    if (token == null) return;
    final request = ++_request;
    _track = track;
    _position = Duration.zero;
    _duration = null;
    _retriedLink = false;
    _advancing = false;
    _loading = true;
    _setStatus(PlayerStatus.loading);
    try {
      final link = await _api.streamLink(token, track.id);
      if (request != _request) return;
      await _engine.load(track, link.url);
      if (request != _request) return;
      _loading = false;
      _engine.play();
      _refreshStatus();
    } catch (_) {
      if (request != _request) return;
      _loading = false;
      _setStatus(PlayerStatus.error);
    }
  }

  /// A finished track moves the queue on, or replays itself on repeat-one.
  Future<void> _onCompleted() async {
    final queue = _queue;
    if (_advancing || queue == null) return;
    _advancing = true;
    final next = queue.next(auto: true);
    if (next == null) {
      _setStatus(PlayerStatus.completed);
    } else if (next.id == _track?.id && _repeat == QueueRepeat.one) {
      _advancing = false;
      await _engine.seek(Duration.zero);
      _engine.play();
    } else {
      await _start(next);
    }
  }

  Future<void> toggle() async {
    switch (_status) {
      case PlayerStatus.playing || PlayerStatus.buffering:
        await pause();
      case PlayerStatus.paused || PlayerStatus.completed || PlayerStatus.error:
        await resume();
      case PlayerStatus.idle || PlayerStatus.loading:
        break;
    }
  }

  Future<void> pause() async {
    if (_status == PlayerStatus.playing || _status == PlayerStatus.buffering) {
      await _engine.pause();
    }
  }

  /// Continues a paused track, replays a completed one from the start, or
  /// retries one that failed.
  Future<void> resume() async {
    switch (_status) {
      case PlayerStatus.paused:
        _engine.play();
      case PlayerStatus.completed:
        _advancing = false;
        await _engine.seek(Duration.zero);
        _engine.play();
      case PlayerStatus.error:
        if (_track != null) await _start(_track!);
      case PlayerStatus.idle ||
            PlayerStatus.loading ||
            PlayerStatus.playing ||
            PlayerStatus.buffering:
        break;
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
    await _engine.seek(position);
  }

  /// Stops playback and forgets the track, for example on logout.
  Future<void> stop() async {
    _request++;
    _queue = null;
    _track = null;
    _position = Duration.zero;
    _duration = null;
    _loading = false;
    await _engine.stop();
    _setStatus(PlayerStatus.idle);
  }

  /// Stream URLs expire; when playback fails (typically on a seek after the
  /// URL expired), fetch a fresh one once and resume where it stopped.
  Future<void> _onEngineError(Object error) async {
    final track = _track;
    final token = _token();
    if (track == null || token == null || _retriedLink) {
      _setStatus(PlayerStatus.error);
      return;
    }
    _retriedLink = true;
    final request = _request;
    final resumeAt = _position;
    try {
      final link = await _api.streamLink(token, track.id);
      if (request != _request) return;
      await _engine.load(track, link.url, start: resumeAt);
      _engine.play();
    } catch (_) {
      if (request == _request) _setStatus(PlayerStatus.error);
    }
  }

  void _refreshStatus() {
    if (_loading || _status == PlayerStatus.error || _track == null) {
      notifyListeners();
      return;
    }
    if (_engineState == EngineState.completed) {
      // Outside the engine's event callback, which it may re-trigger.
      unawaited(Future.microtask(_onCompleted));
      return;
    }
    _setStatus(switch (_engineState) {
      EngineState.completed => PlayerStatus.completed,
      EngineState.loading ||
      EngineState.buffering when _playing =>
        PlayerStatus.buffering,
      _ => _playing ? PlayerStatus.playing : PlayerStatus.paused,
    });
  }

  void _setStatus(PlayerStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _engine.dispose();
    super.dispose();
  }
}
