import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/settings/data/device_settings.dart';
import 'package:rhythmo/features/settings/presentation/device_settings_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.mhdolatabadi.nafir/local_audio');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'permissionStatus' => {
            'audio': true,
            'microphone': false,
            'notifications': true
          },
        'appVersion' => {'version': '0.1.123', 'build_number': '456'},
        'openAppSettings' => true,
        _ => throw PlatformException(code: 'unexpected'),
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('version comes from the installed native package', () async {
    expect(await const PlatformDeviceSettings().appVersion(), '0.1.123+456');
    expect(calls, ['appVersion']);
  });
  testWidgets('permissions are read without requesting or opening settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PermissionsScreen()));
    await tester.pumpAndSettle();
    expect(calls, ['permissionStatus']);
    expect(find.text('مجاز'), findsNWidgets(2));
    expect(find.text('غیرفعال'), findsOneWidget);
    await tester.tap(find.text('بازکردن تنظیمات دستگاه'));
    await tester.pumpAndSettle();
    expect(calls, ['permissionStatus', 'openAppSettings']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('about displays actual version in Persian digits',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: AboutScreen(openPage: (_) async {})));
    await tester.pumpAndSettle();
    expect(find.text('۰.۱.۱۲۳+۴۵۶'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
