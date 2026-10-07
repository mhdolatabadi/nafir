import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'snippet_file_stub.dart' if (dart.library.io) 'snippet_file_io.dart'
    as snippet_file;

/// How long a snippet is recorded: long enough to match, short enough to
/// wait for.
const snippetLength = Duration(seconds: 10);

/// Records a short snippet from the microphone.
abstract interface class SnippetRecorder {
  /// Whether recording works here at all (a microphone, and on the web
  /// `getUserMedia`).
  Future<bool> isSupported();

  /// Asks the system for the microphone, once the app has explained why.
  Future<bool> requestPermission();

  /// Records [length] of audio and returns it as a WAV file's bytes.
  /// [onLevel] hears the loudness, 0 to 1, as it records.
  Future<Uint8List> record(Duration length,
      {void Function(double level)? onLevel});

  /// Stops a recording under way and throws its audio away.
  Future<void> cancel();
}

/// Thrown by [SnippetRecorder.record] after [SnippetRecorder.cancel].
class RecordingCancelled implements Exception {
  const RecordingCancelled();
}

/// The microphone, through the `record` plugin. The snippet is written as
/// WAV to a private temporary file (on the web, kept in memory), read back
/// and deleted right away; it is never kept on the device.
class MicSnippetRecorder implements SnippetRecorder {
  AudioRecorder? _recorder;
  Completer<void>? _stop;
  bool _cancelled = false;

  AudioRecorder get _mic => _recorder ??= AudioRecorder();

  @override
  Future<bool> isSupported() async {
    try {
      return await _mic.isEncoderSupported(AudioEncoder.wav);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _mic.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> record(Duration length,
      {void Function(double level)? onLevel}) async {
    _cancelled = false;
    final stop = _stop = Completer<void>();
    await _mic.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 22050,
        numChannels: 1,
        // Music, not speech: leave the signal as it is.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: await snippet_file.snippetPath(),
    );
    final levels = _mic
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) =>
            onLevel?.call(((amplitude.current + 50) / 50).clamp(0.0, 1.0)));
    final timer = Timer(length, () {
      if (!stop.isCompleted) stop.complete();
    });
    await stop.future;
    timer.cancel();
    await levels.cancel();
    final path = await _mic.stop();
    if (_cancelled || path == null) {
      await snippet_file.discardSnippet(path);
      throw const RecordingCancelled();
    }
    return snippet_file.takeSnippet(path);
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final stop = _stop;
    if (stop != null && !stop.isCompleted) stop.complete();
  }
}
