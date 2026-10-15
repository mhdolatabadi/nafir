import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/features/player/application/playback_settings.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/loudness.dart';
import 'package:nafir/features/settings/presentation/loudness_setting.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

void main() {
  testWidgets('the loudness setting on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryPlaybackSettingsStore();
    final player = PlayerController(
      api: FakeTracksApi(),
      engine: FakeAudioEngine(),
      token: () => 'tok',
      settingsStore: store,
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home:
          Scaffold(body: ListView(children: [LoudnessSetting(player: player)])),
    ));
    await tester.pumpAndSettle();

    // On by default, per track.
    expect(find.text('یکسان‌سازی بلندی صدا'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('هر آلبوم'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final label in ['هر آهنگ', 'هر آلبوم']) {
      expect(
          tester
              .getSize(find.ancestor(
                  of: find.text(label),
                  matching: find.bySubtype<ButtonStyleButton>()))
              .height,
          greaterThanOrEqualTo(48));
    }

    await tester.tap(find.text('هر آلبوم'));
    await tester.pumpAndSettle();
    expect(player.loudness, LoudnessMode.album);
    expect(store.settings.loudness, LoudnessMode.album);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(player.loudness, LoudnessMode.off);
    expect(find.text('هر آلبوم'), findsNothing);
    expect(find.textContaining('همان بلندی که ضبط شده'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(player.loudness, LoudnessMode.track);
    expect(tester.takeException(), isNull);
  });
}
