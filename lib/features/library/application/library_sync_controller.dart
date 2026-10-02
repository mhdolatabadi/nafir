import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nafir/features/library/data/local_audio_upload.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';

/// Which way a track's file is being copied.
enum SyncKind {
  /// From this device's music to the account.
  upload,
}

enum SyncPhase {
  /// Waiting for an earlier transfer to finish.
  queued,
  running,
  failed,
}

/// Why a transfer failed, for a short Persian explanation.
enum SyncError {
  permission,
  quota,
  offline,
  tooLarge,
  unsupportedFormat,
  invalidAudio,
  notFound,
  unknown,
}

/// A transfer of one track's file, shown on its row.
@immutable
class SyncOperation {
  const SyncOperation({
    required this.kind,
    required this.track,
    this.phase = SyncPhase.queued,
    this.progress = 0,
    this.error,
  });

  final SyncKind kind;

  /// The copy being transferred: the device track for an upload.
  final Track track;
  final SyncPhase phase;

  /// 0..1 while running.
  final double progress;
  final SyncError? error;

  bool get active => phase != SyncPhase.failed;

  SyncOperation _copy({SyncPhase? phase, double? progress, SyncError? error}) =>
      SyncOperation(
        kind: kind,
        track: track,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        error: error,
      );
}

/// Copies tracks between this device and the account, one at a time, and
/// remembers each one's state for its row in the library: queued, running
/// with progress, or failed with a reason until retried or dismissed.
///
/// Uploads go through [UploadController], so quota, size and format checks,
/// per-file progress and the cleanup of failed uploads are the same as for
/// picked files. The file is sent as is, never transcoded.
class LibrarySyncController extends ChangeNotifier {
  LibrarySyncController({
    required UploadController uploads,
    required LocalAudioUploadSource uploadSource,
    required Future<void> Function() onUploaded,
  })  : _uploads = uploads,
        _uploadSource = uploadSource,
        _onUploaded = onUploaded;

  final UploadController _uploads;
  final LocalAudioUploadSource _uploadSource;
  final Future<void> Function() _onUploaded;

  /// By the transferred copy's track ID, in the order they were started.
  final Map<String, SyncOperation> _operations = {};
  String? _running;
  bool _draining = false;

  final _finished = StreamController<SyncOperation>.broadcast(sync: true);

  /// Each transfer as it completes or fails, to tell the user; a completed
  /// one has no error and is no longer listed.
  Stream<SyncOperation> get finished => _finished.stream;

  /// The transfer of the copy with [trackId], if any.
  SyncOperation? operationFor(String trackId) => _operations[trackId];
  Iterable<SyncOperation> get operations => _operations.values;

  /// Uploads a device track to the account. Started again when it already
  /// failed; ignored while it is queued or running.
  void upload(Track local) {
    if (!local.isLocal) return;
    final existing = _operations[local.id];
    if (existing != null && existing.active) return;
    _operations[local.id] = SyncOperation(kind: SyncKind.upload, track: local);
    notifyListeners();
    _drain();
  }

  /// Starts a failed transfer again.
  void retry(String trackId) {
    final operation = _operations[trackId];
    if (operation == null || operation.active) return;
    _operations.remove(trackId);
    switch (operation.kind) {
      case SyncKind.upload:
        upload(operation.track);
    }
  }

  /// Stops a queued or running transfer; nothing is left behind.
  void cancel(String trackId) {
    final operation = _operations[trackId];
    if (operation == null || !operation.active) return;
    if (_running == trackId) {
      if (operation.kind == SyncKind.upload) {
        if (!_uploads.canCancel) return;
        _uploads.cancel();
      }
      return;
    }
    _operations.remove(trackId);
    notifyListeners();
  }

  /// Hides a failed transfer's error.
  void dismiss(String trackId) {
    final operation = _operations[trackId];
    if (operation == null || operation.active) return;
    _operations.remove(trackId);
    notifyListeners();
  }

  /// Whether a running transfer of [trackId] can be cancelled right now.
  bool canCancel(String trackId) {
    final operation = _operations[trackId];
    if (operation == null || !operation.active) return false;
    if (_running != trackId) return true;
    return _uploads.canCancel;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final next = _operations.entries
            .where((e) => e.value.phase == SyncPhase.queued)
            .firstOrNull;
        if (next == null) return;
        // A picked file may still be uploading; wait for it.
        if (_uploads.isBusy) {
          await _idle(_uploads);
          continue;
        }
        _running = next.key;
        _set(next.key, next.value._copy(phase: SyncPhase.running));
        await _runUpload(next.key, next.value.track);
        _running = null;
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _runUpload(String id, Track local) async {
    void follow() {
      final operation = _operations[id];
      if (operation == null || operation.phase != SyncPhase.running) return;
      if (_uploads.phase == UploadPhase.uploading) {
        _set(id, operation._copy(progress: _uploads.progress));
      }
    }

    _uploads.readingFile();
    try {
      final file = await _uploadSource.prepare(local);
      _uploads.addListener(follow);
      try {
        await _uploads.upload(file);
      } finally {
        _uploads.removeListener(follow);
      }
    } on PlatformException catch (error) {
      _uploads.pickCancelled();
      return _fail(
        id,
        error.code == 'PERMISSION_DENIED'
            ? SyncError.permission
            : error.code == 'NOT_FOUND'
                ? SyncError.notFound
                : SyncError.unknown,
      );
    } catch (_) {
      _uploads.pickCancelled();
      return _fail(id, SyncError.unknown);
    }

    switch (_uploads.phase) {
      case UploadPhase.done:
        // Kept as running until the list shows the server copy, so the row
        // goes straight from uploading to synced.
        await _onUploaded();
        final operation = _operations.remove(id);
        notifyListeners();
        if (operation != null) _finished.add(operation._copy(progress: 1));
      case UploadPhase.failed:
        _fail(id, _fromUpload(_uploads.error));
      default:
        // Cancelled.
        _operations.remove(id);
        notifyListeners();
    }
  }

  static SyncError _fromUpload(UploadError? error) => switch (error) {
        UploadError.quotaExceeded => SyncError.quota,
        UploadError.network => SyncError.offline,
        UploadError.tooLarge => SyncError.tooLarge,
        UploadError.unsupportedFormat => SyncError.unsupportedFormat,
        UploadError.invalidAudio ||
        UploadError.emptyFile =>
          SyncError.invalidAudio,
        _ => SyncError.unknown,
      };

  void _fail(String id, SyncError error) {
    final operation = _operations[id];
    if (operation == null) return;
    final failed = operation._copy(phase: SyncPhase.failed, error: error);
    _set(id, failed);
    _finished.add(failed);
  }

  void _set(String id, SyncOperation operation) {
    _operations[id] = operation;
    notifyListeners();
  }

  static Future<void> _idle(UploadController uploads) {
    final done = Completer<void>();
    void check() {
      if (!uploads.isBusy && !done.isCompleted) done.complete();
    }

    uploads.addListener(check);
    return done.future.whenComplete(() => uploads.removeListener(check));
  }

  /// Forgets every transfer, for example on logout. A running upload is
  /// cancelled.
  void clear() {
    if (_uploads.canCancel) _uploads.cancel();
    _operations.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _finished.close();
    super.dispose();
  }
}

/// A short Persian explanation of [error], for a snackbar or a row.
String syncErrorMessage(SyncError error) => switch (error) {
      SyncError.permission =>
        'نفیر اجازهٔ دسترسی به موسیقی دستگاه را ندارد. از تنظیمات اندروید اجازه بده.',
      SyncError.quota => 'فضای ابری حسابت پر است. چند آهنگ را حذف کن.',
      SyncError.offline =>
        'اتصال اینترنت برقرار نیست. وصل شو و دوباره تلاش کن.',
      SyncError.tooLarge => 'این فایل از حداکثر اندازهٔ مجاز بزرگ‌تر است.',
      SyncError.unsupportedFormat => 'قالب این فایل پشتیبانی نمی‌شود.',
      SyncError.invalidAudio => 'این فایل صوتی سالم نیست.',
      SyncError.notFound => 'فایل روی دستگاه پیدا نشد.',
      SyncError.unknown => 'کار ناتمام ماند. دوباره تلاش کن.',
    };
