import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/admin/data/admin_account.dart';
import 'package:nafir/features/admin/presentation/admin_screen.dart';
import 'package:nafir/features/auth/data/auth_models.dart';

class FakeAdminApi implements AdminApi {
  bool verified = false;
  bool fail = false;
  bool denied = false;
  String query = '';

  AdminAccount get account => AdminAccount(
        user: AuthUser(
            id: 'account', email: 'member@example.com', verified: verified),
        createdAt: DateTime(2026),
      );

  @override
  Future<AdminAccountPage> listAccounts(String token,
      {String query = '', int offset = 0}) async {
    this.query = query;
    if (denied) throw const ApiException('denied', statusCode: 403);
    return (accounts: [account], hasMore: false);
  }

  @override
  Future<AdminAccount> setAccountVerification(
      String token, String accountId, bool verified) async {
    if (fail) throw const ApiException('unavailable', statusCode: 500);
    this.verified = verified;
    return account;
  }
}

void main() {
  Future<void> pump(WidgetTester tester, FakeAdminApi api) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: AdminScreen(api: api, token: () => 'token'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('search, confirmation, verification and revoke', (tester) async {
    final api = FakeAdminApi();
    await pump(tester, api);
    await tester.enterText(find.byType(TextField), 'member');
    await tester.tap(find.text('جست‌وجو'));
    await tester.pumpAndSettle();
    expect(api.query, 'member');
    await tester.tap(find.text('تأیید حساب'));
    await tester.pumpAndSettle();
    expect(api.verified, isFalse);
    await tester.tap(find.text('تأیید حساب').last);
    await tester.pumpAndSettle();
    expect(api.verified, isTrue);
    expect(find.text('حساب تأییدشده'), findsOneWidget);
    await tester.tap(find.text('لغو تأیید'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لغو تأیید').last);
    await tester.pumpAndSettle();
    expect(api.verified, isFalse);
  });

  testWidgets('failed verification preserves displayed state', (tester) async {
    final api = FakeAdminApi()..fail = true;
    await pump(tester, api);
    await tester.tap(find.text('تأیید حساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأیید حساب').last);
    await tester.pumpAndSettle();
    expect(api.verified, isFalse);
    expect(find.text('تأیید نشده'), findsOneWidget);
    expect(find.text('تغییر ذخیره نشد. دوباره تلاش کن.'), findsOneWidget);
  });

  testWidgets('forbidden directory hides accounts', (tester) async {
    await pump(tester, FakeAdminApi()..denied = true);
    expect(find.text('member@example.com'), findsNothing);
    expect(find.text('دسترسی مدیریت نداری. دوباره وارد حساب مدیر شو.'),
        findsOneWidget);
  });

  testWidgets('narrow screen clears insets and keeps 48px actions',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await pump(tester, FakeAdminApi());
    await tester.ensureVisible(find.text('تأیید حساب'));
    expect(tester.takeException(), isNull);
    final button = find.ancestor(
        of: find.text('تأیید حساب'), matching: find.byType(OutlinedButton));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(button).right, lessThanOrEqualTo(336));
  });
}
