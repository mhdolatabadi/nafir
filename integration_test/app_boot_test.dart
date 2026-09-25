import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nafir/features/player/application/media_session.dart';
import 'package:nafir/main.dart' as app;

/// Runs on a real device or emulator: the real entry point with all
/// platform plugins. CI points API_BASE_URL at a port nothing listens on, so
/// a booted app must end on the "server unavailable" screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app boots and reaches its first screen', (tester) async {
    await app.main();

    final unavailable = find.text('اتصال به سرور برقرار نشد');
    for (var i = 0; i < 60 && unavailable.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(unavailable, findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
    expect(Directionality.of(tester.element(unavailable)), TextDirection.rtl);
    // Background playback: the media service, activity and permissions in
    // AndroidManifest.xml are wired correctly, or AudioService.init throws.
    expect(activeMediaSession, isNotNull);
  });
}
