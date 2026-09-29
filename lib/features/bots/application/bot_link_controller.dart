import 'package:flutter/foundation.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/bots/data/messenger_bot.dart';

enum BotLinkStatus { idle, loading, ready, failed }

/// Which messenger bots exist, and the one-time code that links one of their
/// chats to this account.
class BotLinkController extends ChangeNotifier {
  BotLinkController({
    required BotsApi api,
    required String? Function() token,
    DateTime Function()? now,
  })  : _api = api,
        _token = token,
        _now = now ?? DateTime.now;

  final BotsApi _api;
  final String? Function() _token;
  final DateTime Function() _now;

  BotLinkStatus _status = BotLinkStatus.idle;
  List<MessengerBot> _bots = const [];
  BotLinkCode? _code;
  bool _requesting = false;
  String? _error;

  BotLinkStatus get status => _status;
  List<MessengerBot> get bots => _bots;
  bool get requesting => _requesting;

  /// Why the last code request failed, for people.
  String? get error => _error;

  /// The current code, or null once it has expired.
  BotLinkCode? get code {
    final code = _code;
    return code == null || !code.expiresAt.isAfter(_now()) ? null : code;
  }

  Future<void> load() async {
    final token = _token();
    if (token == null) return;
    _status = BotLinkStatus.loading;
    notifyListeners();
    try {
      _bots = await _api.listBots(token);
      _status = BotLinkStatus.ready;
    } catch (_) {
      _status = BotLinkStatus.failed;
    }
    notifyListeners();
  }

  Future<void> requestCode() async {
    final token = _token();
    if (token == null || _requesting) return;
    _requesting = true;
    _error = null;
    notifyListeners();
    try {
      final code = await _api.createBotLinkCode(token);
      _code = code;
      if (code.bots.isNotEmpty) _bots = code.bots;
    } on ApiException catch (e) {
      _error = e.statusCode == 429
          ? 'کد زیادی درخواست شده است. کمی بعد دوباره امتحان کنید.'
          : 'دریافت کد ناموفق بود. دوباره امتحان کنید.';
    } catch (_) {
      _error = 'دریافت کد ناموفق بود. اتصال اینترنت را بررسی کنید.';
    }
    _requesting = false;
    notifyListeners();
  }

  /// Forgets the code, for example when the account signs out.
  void clear() {
    _code = null;
    _error = null;
    _bots = const [];
    _status = BotLinkStatus.idle;
    notifyListeners();
  }
}
