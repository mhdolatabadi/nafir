import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/bots/data/messenger_bot.dart';

const baleBot =
    MessengerBot(provider: 'bale', name: 'بله', username: 'NafirBot');
const linkedBale = MessengerBot(
    provider: 'bale', name: 'بله', username: 'NafirBot', linked: true);

class FakeBotsApi implements BotsApi {
  FakeBotsApi({this.bots = const [baleBot]});

  final List<MessengerBot> bots;
  Object? codeError;
  Object? sendError;
  final sent = <String>[];
  int codes = 0;
  DateTime expiresAt = DateTime.utc(2026, 9, 29, 12, 10);

  @override
  Future<List<MessengerBot>> listBots(String token) async => bots;

  @override
  Future<void> sendTrackToBot(
      String token, String provider, String trackId) async {
    if (sendError != null) throw sendError!;
    sent.add('$provider/$trackId');
  }

  @override
  Future<BotLinkCode> createBotLinkCode(String token) async {
    if (codeError != null) throw codeError!;
    codes++;
    return BotLinkCode(
      code: '1234567$codes',
      expiresAt: expiresAt,
      bots: [
        for (final bot in bots)
          MessengerBot(
            provider: bot.provider,
            name: bot.name,
            username: bot.username,
            linkUrl: 'https://ble.ir/${bot.username}?start=1234567$codes',
          ),
      ],
    );
  }
}

void main() {
  var now = DateTime.utc(2026, 9, 29, 12);

  BotLinkController controller(FakeBotsApi api, {String? token = 'tok'}) =>
      BotLinkController(api: api, token: () => token, now: () => now);

  test('loads the bots and issues a code', () async {
    final links = controller(FakeBotsApi());
    await links.load();
    expect(links.status, BotLinkStatus.ready);
    expect(links.bots.single.username, 'NafirBot');
    expect(links.code, isNull);

    await links.requestCode();
    expect(links.code?.code, '12345671');
    expect(links.code?.bots.single.linkUrl,
        'https://ble.ir/NafirBot?start=12345671');
    expect(links.error, isNull);
  });

  test('an expired code is no longer shown', () async {
    final links = controller(FakeBotsApi());
    await links.requestCode();
    now = now.add(const Duration(minutes: 11));
    expect(links.code, isNull);
    now = DateTime.utc(2026, 9, 29, 12);
  });

  test('a throttled request explains itself', () async {
    final api = FakeBotsApi()
      ..codeError = const ApiException('429', statusCode: 429);
    final links = controller(api);
    await links.requestCode();
    expect(links.code, isNull);
    expect(links.error, contains('کمی بعد'));
    expect(links.requesting, isFalse);
  });

  test('signed out, nothing is requested; clear forgets the code', () async {
    final api = FakeBotsApi();
    await controller(api, token: null).requestCode();
    expect(api.codes, 0);

    final links = controller(api);
    await links.load();
    await links.requestCode();
    links.clear();
    expect(links.code, isNull);
    expect(links.bots, isEmpty);
  });

  test('only linked bots are offered for sending', () async {
    final links = controller(FakeBotsApi(bots: const [baleBot]));
    await links.load();
    expect(links.linkedBots, isEmpty);

    final linked = controller(FakeBotsApi(bots: const [linkedBale]));
    await linked.load();
    expect(linked.linkedBots.single.provider, 'bale');
  });

  test('sending reports each outcome', () async {
    final api = FakeBotsApi(bots: const [linkedBale]);
    final links = controller(api);
    await links.load();

    expect(await links.send('bale', 't1'), BotSendResult.queued);
    expect(api.sent, ['bale/t1']);

    api.sendError = const ApiException('409', statusCode: 409);
    expect(await links.send('bale', 't1'), BotSendResult.notLinked);
    api.sendError = const ApiException('413', statusCode: 413);
    expect(await links.send('bale', 't1'), BotSendResult.tooLarge);
    api.sendError = Exception('offline');
    expect(await links.send('bale', 't1'), BotSendResult.failed);
  });
}
