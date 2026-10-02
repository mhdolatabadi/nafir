import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/link_import/data/link_import.dart';

/// The outcome of submitting a link: queued, or refused with a message.
typedef LinkSubmitResult = ({bool queued, String message});

/// Adds music from links and remembers which of this session's imports
/// failed, so the library can say why. Progress itself shows with the
/// library's imports in progress.
class LinkImportController extends ChangeNotifier {
  LinkImportController({
    required LinkImportsApi api,
    required String? Function() token,
  })  : _api = api,
        _token = token;

  final LinkImportsApi _api;
  final String? Function() _token;

  /// Imports started here and not yet seen finished.
  final Set<String> _pending = {};

  bool _submitting = false;
  bool get submitting => _submitting;

  List<LinkImport> _failures = const [];

  /// This session's imports that failed, newest first, until dismissed.
  List<LinkImport> get failures => _failures;

  bool get hasPending => _pending.isNotEmpty;

  Future<LinkSubmitResult> submit(String url) async {
    final token = _token();
    if (token == null) {
      return (queued: false, message: linkImportMessage(null));
    }
    _submitting = true;
    notifyListeners();
    try {
      final job = await _api.importFromLink(token, url.trim());
      _pending.add(job.id);
      return (
        queued: true,
        message:
            'در حال اضافه کردن «${job.fileName}»؛ وقتی آماده شد در کتابخانه می‌آید.',
      );
    } on ApiException catch (e) {
      return (queued: false, message: linkImportMessage(e.code));
    } catch (_) {
      return (queued: false, message: linkImportMessage(null));
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Checks how this session's imports ended, for example once the library
  /// has no imports in progress left.
  Future<void> refresh() async {
    final token = _token();
    if (token == null || _pending.isEmpty) return;
    try {
      final recent = await _api.listLinkImports(token);
      final failed = <LinkImport>[];
      for (final job in recent) {
        if (!_pending.contains(job.id) || !job.finished) continue;
        _pending.remove(job.id);
        if (job.state == LinkImportState.failed) failed.add(job);
      }
      if (failed.isNotEmpty) {
        _failures = [...failed, ..._failures];
      }
      notifyListeners();
    } catch (_) {
      // Tried again on the next refresh.
    }
  }

  void dismissFailures() {
    _failures = const [];
    notifyListeners();
  }

  void clear() {
    _pending.clear();
    _failures = const [];
    notifyListeners();
  }
}
