import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';
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

/// Plays one track at a time from a short-lived stream URL.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required TracksApi api,
    required AudioEngine engine,
    required String? Function() token,
  })  : _api = api,
        _engine = engine,
        _token = token {
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
  late final List<StreamSubscription<Object?>> _subscriptions;

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
  PlayerStatus get status => _status;
  Duration get position => _position;
  Duration? get duration => _duration;

  /// Plays [track], or toggles pause when it is already the current track.
  Future<void> play(Track track) async {
    if (_track?.id == track.id && _status != PlayerStatus.error) {
      return toggle();
    }
    final token = _token();
    if (token == null) return;
    final request = ++_request;
    _track = track;
    _position = Duration.zero;
    _duration = null;
    _retriedLink = false;
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

  Future<void> toggle() async {
    switch (_status) {
      case PlayerStatus.playing || PlayerStatus.buffering:
        await _engine.pause();
      case PlayerStatus.completed:
        await _engine.seek(Duration.zero);
        _engine.play();
      case PlayerStatus.paused:
        _engine.play();
      case PlayerStatus.error:
        if (_track != null) await play(_track!);
      case PlayerStatus.idle || PlayerStatus.loading:
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
