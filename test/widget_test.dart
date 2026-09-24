import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/data/auth_models.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/data/upload_models.dart';
import 'package:nafir/main.dart';

import 'upload_controller_test.dart' show FakeTracksApi, FakeUploader;

const _user = AuthUser(id: 'u1', email: 'listener@example.com');

class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.validToken = 'valid-token', this.meError});

  final String validToken;
  final Object? meError;
  final registered = <String>{};

  @override
  Future<AuthSession> login(String email, String password) async {
    if (email != _user.email || password != 'correct horse') {
      throw const ApiException('401',
          statusCode: 401, code: 'invalid_credentials');
    }
    return AuthSession(token: validToken, user: _user);
  }

  @override
  Future<AuthSession> register(String email, String password) async {
    if (!registered.add(email)) {
      throw const ApiException('409', statusCode: 409, code: 'email_taken');
    }
    return AuthSession(
        token: validToken, user: AuthUser(id: 'u2', email: email));
  }

  @override
  Future<AuthUser> me(String token) async {
    if (meError != null) throw meError!;
    if (token != validToken) {
      throw const ApiException('401', statusCode: 401, code: 'unauthorized');
    }
    return _user;
  }
}

class FakePicker implements AudioPicker {
  FakePicker(this.file);

  final PickedAudio? file;

  @override
  Future<PickedAudio?> pick() async => file;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required TokenStore tokenStore,
  AuthApi? api,
  FakeUploader? uploader,
  AudioPicker? picker,
}) async {
  await tester.pumpWidget(NafirApp(
    healthCheck: () async {},
    authApi: api ?? FakeAuthApi(),
    tokenStore: tokenStore,
    tracksApi: FakeTracksApi(),
    uploader: uploader ?? FakeUploader(),
    picker: picker ?? FakePicker(null),
  ));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'ایمیل'), email);
  await tester.enterText(
      find.widgetWithText(TextFormField, 'رمز عبور'), password);
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows setup instructions without API configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const NafirApp());

    expect(find.textContaining('API_BASE_URL'), findsOneWidget);
  });

  testWidgets('shows retry when the API is unavailable', (tester) async {
    await tester.pumpWidget(
      NafirApp(healthCheck: () async => throw Exception('offline')),
    );
    await tester.pumpAndSettle();

    expect(find.text('اتصال به سرور برقرار نشد'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('without a saved token the sign-in screen is shown', (
    tester,
  ) async {
    await _pumpApp(tester, tokenStore: MemoryTokenStore());

    expect(find.text('ورود به نفیر'), findsOneWidget);
  });

  testWidgets('signing in opens the library and saves the token', (
    tester,
  ) async {
    final tokens = MemoryTokenStore();
    await _pumpApp(tester, tokenStore: tokens);

    await _submit(tester, 'listener@example.com', 'correct horse');

    expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
    expect(await tokens.read(), 'valid-token');
  });

  testWidgets('wrong credentials show an error and stay signed out', (
    tester,
  ) async {
    final tokens = MemoryTokenStore();
    await _pumpApp(tester, tokenStore: tokens);

    await _submit(tester, 'listener@example.com', 'wrong horse');

    expect(find.text('ایمیل یا رمز عبور درست نیست.'), findsOneWidget);
    expect(await tokens.read(), isNull);
  });

  testWidgets('registering creates a session; a taken email is reported', (
    tester,
  ) async {
    final api = FakeAuthApi()..registered.add('taken@example.com');
    await _pumpApp(tester, tokenStore: MemoryTokenStore(), api: api);
    await tester.tap(find.text('حساب نداری؟ ثبت‌نام کن'));
    await tester.pumpAndSettle();

    await _submit(tester, 'taken@example.com', 'long enough');
    expect(find.text('با این ایمیل قبلاً حساب ساخته شده است.'), findsOneWidget);

    await _submit(tester, 'new@example.com', 'long enough');
    expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
  });

  testWidgets('registration rejects a short password before calling the API', (
    tester,
  ) async {
    await _pumpApp(tester, tokenStore: MemoryTokenStore());
    await tester.tap(find.text('حساب نداری؟ ثبت‌نام کن'));
    await tester.pumpAndSettle();

    await _submit(tester, 'new@example.com', 'short');

    expect(find.text('رمز عبور باید حداقل ۸ کاراکتر باشد.'), findsOneWidget);
  });

  testWidgets('a saved valid token restores the session', (tester) async {
    await _pumpApp(tester, tokenStore: MemoryTokenStore('valid-token'));

    expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
  });

  testWidgets('a rejected saved token is cleared and sign-in is shown', (
    tester,
  ) async {
    final tokens = MemoryTokenStore('expired-token');
    await _pumpApp(tester, tokenStore: tokens);

    expect(find.text('ورود به نفیر'), findsOneWidget);
    expect(await tokens.read(), isNull);
  });

  testWidgets('a network failure during restore keeps the token for retry', (
    tester,
  ) async {
    final tokens = MemoryTokenStore('valid-token');
    await _pumpApp(
      tester,
      tokenStore: tokens,
      api: FakeAuthApi(meError: Exception('offline')),
    );

    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(await tokens.read(), 'valid-token');
  });

  testWidgets('logging out clears the token and returns to sign-in', (
    tester,
  ) async {
    final tokens = MemoryTokenStore('valid-token');
    await _pumpApp(tester, tokenStore: tokens);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('ورود به نفیر'), findsOneWidget);
    expect(await tokens.read(), isNull);
  });

  testWidgets('picking a file uploads it and shows the result', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      tokenStore: MemoryTokenStore('valid-token'),
      picker: FakePicker(PickedAudio(
        name: 'song.mp3',
        sizeBytes: 4,
        openRead: () => Stream.value([1, 2, 3, 4]),
      )),
    );

    await tester.tap(find.text('افزودن موسیقی'));
    await tester.pumpAndSettle();

    expect(find.text('«Song» به کتابخانه اضافه شد.'), findsOneWidget);
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.textContaining('به کتابخانه اضافه شد'), findsNothing);
  });

  testWidgets('an unsupported file shows an error', (tester) async {
    await _pumpApp(
      tester,
      tokenStore: MemoryTokenStore('valid-token'),
      picker: FakePicker(PickedAudio(
        name: 'notes.txt',
        sizeBytes: 4,
        openRead: () => const Stream.empty(),
      )),
    );

    await tester.tap(find.text('افزودن موسیقی'));
    await tester.pumpAndSettle();

    expect(find.textContaining('این قالب پشتیبانی نمی‌شود'), findsOneWidget);
  });
}
