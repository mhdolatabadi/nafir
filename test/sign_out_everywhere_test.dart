import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';
import 'package:nafir/features/settings/presentation/settings_screen.dart';

import 'cache_controller_test.dart' show FakeAudioCache;
import 'widget_test.dart' show FakeAuthApi;

Widget _settings(Future<void> Function() signOut,
        {EdgeInsets padding = EdgeInsets.zero}) =>
    MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: padding),
          child: SettingsScreen(
            cache:
                CacheController(cache: FakeAudioCache(), playing: () => null),
            email: 'listener@example.com',
            onDeleteAccount: (_) async {},
            onSignOutEverywhere: signOut,
          ),
        ),
      ),
    );

const _tile = 'خروج از همه‌ی دستگاه‌ها';
final _page = find.byType(Scrollable).first;

void main() {
  test('revokeSessions posts to the revoke endpoint and returns the session',
      () async {
    late http.Request sent;
    final client = ApiClient(Uri.parse('https://music.example.com'),
        httpClient: MockClient((request) async {
      sent = request;
      return http.Response(
          jsonEncode({
            'token': 'n3w',
            'expiresAt': '2030-01-01T00:00:00Z',
            'user': {'id': 'u1', 'email': 'listener@example.com'},
          }),
          200,
          headers: {'content-type': 'application/json'});
    }));

    final session = await client.revokeSessions('0ld');

    expect(sent.method, 'POST');
    expect(sent.url.toString(),
        'https://music.example.com/api/v1/auth/sessions/revoke');
    expect(sent.headers['Authorization'], 'Bearer 0ld');
    expect(session.token, 'n3w');
  });

  test('signing out everywhere keeps this device signed in on a new token',
      () async {
    final tokens = MemoryTokenStore('valid-token');
    final api = FakeAuthApi();
    final auth = AuthController(api: api, tokenStore: tokens);
    await auth.restore();

    await auth.signOutEverywhere();

    expect(api.revoked, ['valid-token']);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.token, 'rotated-token');
    expect(await tokens.read(), 'rotated-token');
  });

  test('signing out everywhere needs a session', () async {
    final auth =
        AuthController(api: FakeAuthApi(), tokenStore: MemoryTokenStore());
    await auth.restore();
    await expectLater(auth.signOutEverywhere(), throwsStateError);
  });

  testWidgets('the setting asks first, then confirms on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(_settings(() async => calls++,
        padding: const EdgeInsets.only(bottom: 48)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(_tile), 200, scrollable: _page);
    expect(tester.takeException(), isNull);
    expect(
        tester
            .getSize(find.ancestor(
                of: find.text(_tile), matching: find.byType(ListTile)))
            .height,
        greaterThanOrEqualTo(48));

    // Cancelling does nothing.
    await tester.tap(find.text(_tile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(calls, 0);

    await tester.tap(find.text(_tile));
    await tester.pumpAndSettle();
    expect(find.text('از همه‌ی دستگاه‌ها خارج شوی؟'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('خروج از بقیه'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('از همه‌ی دستگاه‌های دیگر خارج شدی.'), findsOneWidget);
  });

  testWidgets('a failure is reported', (tester) async {
    await tester.pumpWidget(_settings(
        () async => throw const ApiException('503', statusCode: 503)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(_tile), 200, scrollable: _page);
    await tester.tap(find.text(_tile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خروج از بقیه'));
    await tester.pumpAndSettle();
    expect(find.text('خروج از دستگاه‌های دیگر ناموفق بود. دوباره امتحان کن.'),
        findsOneWidget);
  });
}
