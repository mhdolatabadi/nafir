import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The playback speeds offered, slowest first. Pitch is kept at every speed.
const playbackSpeeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// The longest crossfade the settings offer.
const maxCrossfade = Duration(seconds: 8);

/// Listening preferences kept between sessions.
class PlaybackSettings {
  const PlaybackSettings({this.speed = 1, this.crossfade = Duration.zero});

  final double speed;

  /// How long consecutive tracks overlap; zero is off.
  final Duration crossfade;

  /// Reads saved settings, dropping values the app no longer offers.
  factory PlaybackSettings.fromJson(Object? json) {
    if (json is! Map) return const PlaybackSettings();
    final speed = json['speed'];
    final crossfadeMs = json['crossfadeMs'];
    return PlaybackSettings(
      speed: speed is num && playbackSpeeds.contains(speed.toDouble())
          ? speed.toDouble()
          : 1,
      crossfade: crossfadeMs is int
          ? Duration(
              milliseconds: crossfadeMs.clamp(0, maxCrossfade.inMilliseconds))
          : Duration.zero,
    );
  }

  Map<String, Object> toJson() =>
      {'speed': speed, 'crossfadeMs': crossfade.inMilliseconds};

  PlaybackSettings copyWith({double? speed, Duration? crossfade}) =>
      PlaybackSettings(
        speed: speed ?? this.speed,
        crossfade: crossfade ?? this.crossfade,
      );
}

/// Where [PlaybackSettings] are kept between launches.
abstract interface class PlaybackSettingsStore {
  Future<PlaybackSettings> read();
  Future<void> write(PlaybackSettings settings);
}

/// Keeps playback settings on this device, next to the session token.
class SecurePlaybackSettingsStore implements PlaybackSettingsStore {
  SecurePlaybackSettingsStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'nafir.playback_settings';

  final FlutterSecureStorage _storage;

  @override
  Future<PlaybackSettings> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null
        ? const PlaybackSettings()
        : PlaybackSettings.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> write(PlaybackSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));
}

class MemoryPlaybackSettingsStore implements PlaybackSettingsStore {
  MemoryPlaybackSettingsStore([this.settings = const PlaybackSettings()]);

  PlaybackSettings settings;

  @override
  Future<PlaybackSettings> read() async => settings;

  @override
  Future<void> write(PlaybackSettings settings) async =>
      this.settings = settings;
}
