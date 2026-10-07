import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/auth_models.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/auth/presentation/email_verification_screen.dart';
import 'package:nafir/main.dart';

import 'cache_controller_test.dart' show FakeAudioCache;
import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi, FakeUploader;
import 'widget_test.dart' show FakeAuthApi, FakePicker;

const _unverified =
    AuthUser(id: 'u1', email: 'new@example.com', emailVerified: false);

/// An account that has not verified its email; the code is 123456.
class UnverifiedAuthApi extends FakeAuthApi {
  AuthUser user = _unverified;
  final codes = <String>[];
  final sent = <String>[];
  int attemptsLeft = 5;

  @override
  Future<AuthUser> me(String token) async => user;

  @override
  Future<DateTime> sendEmailCode(String token) async {
    sent.add(user.email);
    return DateTime.now().add(const Duration(minutes: 15));
  }

  @override
  Future<AuthUser> verifyEmail(String token, String code) async {
    codes.add(code);
    if (code != '123456' && code != '۱۲۳۴۵۶') {
      attemptsLeft--;
      throw ApiException('400',
          statusCode: 400,
          code: 'wrong_code',
          details: {'error': 'wrong_code', 'attemptsLeft': attemptsLeft});
    }
    return user = AuthUser(id: user.id, email: user.email);
  }

  @override
  Future<({AuthUser user, bool codeSent})> changeEmail(
      String token, String email) async {
    if (email == 'taken@example.com') {
      throw const ApiException('409', statusCode: 409, code: 'email_taken');
    }
    user = AuthUser(id: user.id, email: email, emailVerified: false);
    sent.add(email);
    return (user: user, codeSent: true);
  }
}

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpApp(WidgetTester tester, FakeAuthApi api) async {
  await tester.pumpWidget(NafirApp(
    healthCheck: () async {},
    authApi: api,
    tokenStore: MemoryTokenStore('valid-token'),
    tracksApi: FakeTracksApi(),
    audioEngine: FakeAudioEngine(),
    audioCache: FakeAudioCache(),
    uploader: FakeUploader(),
    picker: FakePicker(null),
  ));
  await tester.pumpAndSettle();
}

/// Every tappable control on screen is at least 48 px tall and inside 360 px.
void _expectTouchable(WidgetTester tester) {
  for (final finder in [
    find.byType(FilledButton),
    find.byType(TextButton),
    find.byType(OutlinedButton),
  ]) {
    for (final element in finder.evaluate()) {
      final box = tester.getRect(find.byWidget(element.widget));
      expect(box.height, greaterThanOrEqualTo(48), reason: '$element');
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(360));
    }
  }
}

void main() {
  testWidgets(
      'an unverified account sees the reminder and verifies on a 360 px phone',
      (tester) async {
    _narrow(tester);
    final api = UnverifiedAuthApi();
    await _pumpApp(tester, api);

    expect(find.text('ایمیلت را تأیید کن'), findsOneWidget);
    final reminder = tester.getRect(find.byType(EmailVerificationBanner));
    expect(reminder.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'تأیید ایمیل'));
    await tester.pumpAndSettle();

    expect(find.text('کد را از ایمیلت وارد کن'), findsOneWidget);
    expect(find.textContaining('new@example.com'), findsOneWidget);
    _expectTouchable(tester);
    expect(tester.takeException(), isNull);

    // A short code is caught before asking the server.
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.widgetWithText(FilledButton, 'تأیید'));
    await tester.pumpAndSettle();
    expect(find.text('کد ۶ رقمی‌ای را که برایت ایمیل شد وارد کن.'),
        findsOneWidget);
    expect(api.codes, isEmpty);

    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.widgetWithText(FilledButton, 'تأیید'));
    await tester.pumpAndSettle();
    expect(find.text('کد درست نیست. ۴ بار دیگر می‌توانی امتحان کنی.'),
        findsOneWidget);

    // Typed with Persian digits.
    await tester.enterText(find.byType(TextField), '۱۲۳ ۴۵۶');
    await tester.tap(find.widgetWithText(FilledButton, 'تأیید'));
    await tester.pumpAndSettle();
    expect(api.codes.last, '۱۲۳۴۵۶');
    expect(find.text('ایمیلت تأیید شد. همه‌چیز آماده است.'), findsOneWidget);
    // Back in the library, without the reminder.
    expect(find.byType(EmailVerificationScreen), findsNothing);
    expect(find.byType(EmailVerificationBanner), findsNothing);
  });

  testWidgets('a verified account sees no reminder', (tester) async {
    _narrow(tester);
    await _pumpApp(tester, FakeAuthApi());
    expect(find.byType(EmailVerificationBanner), findsNothing);
  });

  testWidgets('resending waits a minute; a mistyped email can be corrected',
      (tester) async {
    _narrow(tester);
    final api = UnverifiedAuthApi();
    final controller =
        AuthController(api: api, tokenStore: MemoryTokenStore('valid-token'));
    await controller.restore();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: EmailVerificationScreen(
          controller: controller,
          resendCooldown: const Duration(seconds: 3),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'ارسال دوباره'));
    await tester.pump();
    expect(api.sent, ['new@example.com']);
    expect(find.text('کد تازه‌ای به ایمیلت فرستاده شد.'), findsOneWidget);
    final waiting = find.widgetWithText(TextButton, 'ارسال دوباره (۳)');
    expect(waiting, findsOneWidget);
    expect(tester.widget<TextButton>(waiting).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(find.widgetWithText(TextButton, 'ارسال دوباره'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'ویرایش ایمیل'));
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(field, 'not-an-email');
    await tester.tap(find.text('ذخیره و ارسال کد'));
    await tester.pumpAndSettle();
    expect(find.text('نشانی ایمیل درست نیست.'), findsOneWidget);

    await tester.enterText(field, 'taken@example.com');
    await tester.tap(find.text('ذخیره و ارسال کد'));
    await tester.pumpAndSettle();
    expect(find.text('این ایمیل برای حساب دیگری ثبت شده است.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'ویرایش ایمیل'));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'right@example.com');
    await tester.tap(find.text('ذخیره و ارسال کد'));
    await tester.pumpAndSettle();
    expect(controller.user!.email, 'right@example.com');
    expect(api.sent.last, 'right@example.com');
    expect(find.textContaining('right@example.com'), findsOneWidget);
    expect(find.text('ایمیل عوض شد و کد تازه به نشانی جدید فرستاده شد.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  test('users from servers without email verification count as verified', () {
    expect(
        AuthUser.fromJson({'id': 'u', 'email': 'a@b.c'}).emailVerified, isTrue);
    expect(
        AuthUser.fromJson({'id': 'u', 'email': 'a@b.c', 'emailVerified': false})
            .emailVerified,
        isFalse);
  });
}
