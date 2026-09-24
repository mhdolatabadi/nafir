import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/data/audio_formats.dart';
import 'package:nafir/features/upload/data/storage_uploader.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

enum UploadPhase {
  idle,

  /// The picker is copying the chosen file into the app.
  reading,
  preparing,
  uploading,
  verifying,
  done,
  failed,
}

/// Why an upload failed, for the UI to explain.
enum UploadError {
  unsupportedFormat,
  tooLarge,
  emptyFile,
  invalidAudio,
  network,
  unknown,
}

/// Uploads one file at a time: reserve a track, send the file straight to
/// storage, then ask the API to verify it. A failed upload leaves nothing
/// behind on the server.
class UploadController extends ChangeNotifier {
  UploadController({
    required TracksApi api,
    required StorageUploader uploader,
    required String? Function() token,
  })  : _api = api,
        _uploader = uploader,
        _token = token;

  final TracksApi _api;
  final StorageUploader _uploader;
  final String? Function() _token;

  UploadPhase _phase = UploadPhase.idle;
  String? _fileName;
  double _progress = 0;
  UploadError? _error;
  Track? _uploaded;

  UploadPhase get phase => _phase;
  String? get fileName => _fileName;

  /// 0..1 while uploading.
  double get progress => _progress;
  UploadError? get error => _error;
  Track? get uploaded => _uploaded;
  bool get isBusy =>
      _phase == UploadPhase.reading ||
      _phase == UploadPhase.preparing ||
      _phase == UploadPhase.uploading ||
      _phase == UploadPhase.verifying;

  /// Verification is a short server call; everything before it can be stopped.
  bool get canCancel =>
      _phase == UploadPhase.preparing || _phase == UploadPhase.uploading;

  Completer<void>? _cancel;

  /// Shows that a picked file is being read before [upload] starts.
  void readingFile() {
    if (isBusy) return;
    _fileName = null;
    _setPhase(UploadPhase.reading);
  }

  /// Ends [readingFile] when the user closed the picker without choosing.
  void pickCancelled() {
    if (_phase == UploadPhase.reading) _setPhase(UploadPhase.idle);
  }

  /// Stops the current upload; the half-created track is removed and the
  /// controller returns to idle.
  void cancel() {
    if (!canCancel) return;
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  Future<void> upload(PickedAudio file) async {
    if (isBusy && _phase != UploadPhase.reading) return;
    _fileName = file.name;
    _progress = 0;
    _error = null;
    _uploaded = null;
    try {
      final contentType = contentTypeFor(file.name);
      if (contentType == null) return _fail(UploadError.unsupportedFormat);
      if (file.sizeBytes <= 0) return _fail(UploadError.emptyFile);
      if (file.sizeBytes > maxUploadBytes) return _fail(UploadError.tooLarge);
      await _run(file, contentType);
    } finally {
      await file.release?.call();
    }
  }

  void dismiss() {
    if (isBusy) return;
    _phase = UploadPhase.idle;
    notifyListeners();
  }

  Future<void> _run(PickedAudio file, String contentType) async {
    final token = _token();
    if (token == null) return _fail(UploadError.unknown);

    final cancel = _cancel = Completer<void>();
    _setPhase(UploadPhase.preparing);
    UploadTicket ticket;
    try {
      ticket = await _api.createUpload(token, file.name, file.sizeBytes);
    } catch (error) {
      if (cancel.isCompleted) return _setPhase(UploadPhase.idle);
      return _fail(_classify(error));
    }

    try {
      if (cancel.isCompleted) throw const UploadCancelled();
      _setPhase(UploadPhase.uploading);
      await _uploader.upload(
        ticket,
        file,
        contentType: contentType,
        onProgress: (sent, total) {
          if (cancel.isCompleted) return;
          _progress = total > 0 ? sent / total : 0;
          notifyListeners();
        },
        cancelled: cancel.future,
      );
      _setPhase(UploadPhase.verifying);
      _uploaded = await _api.completeUpload(token, ticket.track.id);
      _setPhase(UploadPhase.done);
    } catch (error) {
      // The server already discards files it rejects; for anything else,
      // remove the half-finished track so nothing is left behind.
      if (!(error is ApiException && error.code == 'invalid_audio')) {
        try {
          await _api.deleteTrack(token, ticket.track.id);
        } catch (_) {}
      }
      if (error is UploadCancelled) return _setPhase(UploadPhase.idle);
      _fail(_classify(error));
    } finally {
      _cancel = null;
    }
  }

  static UploadError _classify(Object error) {
    if (error is UploadFailed) return UploadError.network;
    if (error is! ApiException) return UploadError.network;
    return switch (error.code) {
      'unsupported_format' => UploadError.unsupportedFormat,
      'invalid_size' => UploadError.tooLarge,
      'invalid_audio' => UploadError.invalidAudio,
      _ => UploadError.unknown,
    };
  }

  void _setPhase(UploadPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  void _fail(UploadError error) {
    _error = error;
    _setPhase(UploadPhase.failed);
  }
}
