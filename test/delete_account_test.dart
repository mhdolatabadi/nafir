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
import 'package:nafir/features/settings/presentation/delete_account_screen.dart';
import 'package:nafir/features/settings/presentation/settings_screen.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';

import 'cache_controller_test.dart' show FakeAudioCache;
import 'widget_test.dart' show FakeAuthApi;

Widget _app(Widget home, {EdgeInsets padding = EdgeInsets.zero}) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: padding),
          child: home,
        ),
      ),
    );

/// A button by its label, whichever constructor built it.
Finder _button(String label) => find.ancestor(
    of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());

final _page = find.byType(Scrollable).first;

void main() {
  test('deleteAccount sends DELETE /api/v1/me with the password', () async {
    late http.Request sent;
    final client = ApiClient(Uri.parse('https://music.example.com'),
        httpClient: MockClient((request) async {
      sent = request;
      return http.Response('', 204);
    }));

    await client.deleteAccount('t0ken', 'correct horse');

    expect(sent.method, 'DELETE');
    expect(sent.url.toString(), 'https://music.example.com/api/v1/me');
    expect(sent.headers['Authorization'], 'Bearer t0ken');
    expect(jsonDecode(sent.body), {'password': 'correct horse'});
  });

  test('a wrong password is reported by its error code', () async {
    final client = ApiClient(Uri.parse('https://music.example.com'),
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'error': 'invalid_password'}), 403)));

    expect(
      () => client.deleteAccount('t0ken', 'nope'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invalid_password')
          .having((e) => e.isUnauthorized, 'isUnauthorized', false)),
    );
  });

  test('AuthController signs out only after the account is deleted', () async {
    final tokens = MemoryTokenStore('valid-token');
    final api = FakeAuthApi();
    final auth = AuthController(api: api, tokenStore: tokens);
    await auth.restore();

    await expectLater(
        auth.deleteAccount('wrong'), throwsA(isA<ApiException>()));
    expect(auth.status, AuthStatus.signedIn);
    expect(await tokens.read(), 'valid-token');

    await auth.deleteAccount('correct horse');
    expect(api.deleted, ['valid-token']);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.token, isNull);
    expect(await tokens.read(), isNull);
  });

  testWidgets(
      'the delete screen fits a 360 px phone and the system bar never '
      'covers its actions', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    await tester.pumpWidget(_app(
      DeleteAccountScreen(
        email: 'a-very-long-address.for-a-narrow-phone@example.com',
        onDelete: (_) async {},
        onOpenPage: opened.add,
      ),
      padding: const EdgeInsets.only(bottom: 48),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final delete = _button('حذف حساب برای همیشه');
    final cancel = _button('انصراف');
    final privacy = _button('حریم خصوصی');
    for (final target in [delete, cancel, privacy]) {
      await tester.scrollUntilVisible(target, 200, scrollable: _page);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    // Scrolled to the end, the last link sits above the system bar.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getRect(privacy).bottom, lessThanOrEqualTo(640 - 48));

    await tester.tap(privacy);
    await tester.tap(_button('راهنمای حذف حساب'));
    expect(opened, ['/privacy', '/delete-account']);
  });

  testWidgets('an empty password is caught before calling the server',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(DeleteAccountScreen(
      email: 'a@example.com',
      onDelete: (_) async => calls++,
    )));
    final delete = _button('حذف حساب برای همیشه');
    await tester.scrollUntilVisible(delete, 200, scrollable: _page);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('رمز عبور را وارد کن.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('server refusals are explained in Persian', (tester) async {
    Object failure =
        const ApiException('429', statusCode: 429, code: 'rate_limited');
    await tester.pumpWidget(_app(DeleteAccountScreen(
      email: 'a@example.com',
      onDelete: (_) async => throw failure,
    )));
    final delete = _button('حذف حساب برای همیشه');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'رمز عبور'), 'correct horse');
    await tester.scrollUntilVisible(delete, 200, scrollable: _page);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.textContaining('کمی بعد دوباره امتحان کن'), findsOneWidget);

    failure = Exception('offline');
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.textContaining('اتصال به سرور برقرار نشد'), findsOneWidget);
  });

  testWidgets('Settings links the privacy policy on the Nafir site',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_app(SettingsScreen(
      cache: CacheController(cache: FakeAudioCache(), playing: () => null),
      email: 'a@example.com',
      onDeleteAccount: (_) async {},
      siteUri: (path) => Uri.parse('https://nafir.example.com').resolve(path),
      openLink: (uri) async {
        opened.add(uri);
        return true;
      },
    )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('حریم خصوصی'), 200,
        scrollable: _page);
    await tester.tap(find.text('حریم خصوصی'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://nafir.example.com/privacy')]);

    await tester.scrollUntilVisible(find.text('حذف حساب کاربری'), 200,
        scrollable: _page);
    await tester.tap(find.text('حذف حساب کاربری'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('راهنمای حذف حساب'), 200,
        scrollable: _page);
    await tester.tap(find.text('راهنمای حذف حساب'));
    await tester.pumpAndSettle();
    expect(opened.last, Uri.parse('https://nafir.example.com/delete-account'));
  });

  testWidgets('a page that cannot open is reported', (tester) async {
    await tester.pumpWidget(_app(SettingsScreen(
      cache: CacheController(cache: FakeAudioCache(), playing: () => null),
      siteUri: (_) => null,
      openLink: (_) async => true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('حذف حساب کاربری'), findsNothing);
    await tester.scrollUntilVisible(find.text('حریم خصوصی'), 200,
        scrollable: _page);
    await tester.tap(find.text('حریم خصوصی'));
    await tester.pumpAndSettle();
    expect(find.text('باز کردن صفحه ممکن نشد.'), findsOneWidget);
  });
}
