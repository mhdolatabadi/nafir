import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/journey/application/listening_journey.dart';
import 'package:rhythmo/features/journey/application/monthly_card.dart';
import 'package:rhythmo/features/journey/data/monthly_card_export.dart';
import 'package:rhythmo/features/journey/presentation/monthly_card_section.dart';
import 'recently_played_test.dart' show track;

class CardSaver implements MonthlyCardSaver {
  int calls = 0;
  bool fail = false;
  bool cancelled = false;
  String? name;
  @override
  Future<MonthlyCardSaveResult> save(Uint8List bytes, String fileName) async {
    calls++;
    if (fail) throw Exception('storage unavailable');
    if (cancelled) return MonthlyCardSaveResult.cancelled;
    name = fileName;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    return MonthlyCardSaveResult.saved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('month snapshots are immutable and account scoped', () async {
    var now = DateTime(2026, 9, 30);
    final journey = ListeningJourney(now: () => now);
    await journey.selectAccount('alice');
    journey.record(track('a'));
    now = DateTime(2026, 10, 1);
    journey.record(track('b'));
    expect(journey.months, ['2026-10', '2026-09']);
    expect(journey.playsForMonth('2026-09'), {'a': 1});
    expect(() => journey.playsForMonth('2026-09')['a'] = 10,
        throwsUnsupportedError);
    final generation = journey.accountGeneration;
    await journey.saved;
    await journey.selectAccount('bob');
    expect(journey.accountGeneration, greaterThan(generation));
    expect(journey.playsForMonth('2026-09'), isEmpty);
    journey.dispose();
  });

  test('top tracks are distinct and deleted tracks are omitted', () {
    final plays = {'a': 2, 'b': 4, 'deleted': 8};
    final card = MonthlyListeningCard(
        month: '2026-10',
        plays: plays,
        library: [track('a'), track('b'), track('a')]);
    plays['a'] = 500;
    expect(card.total, 14);
    expect(card.topTracks.map((t) => t.id), ['b', 'a']);
    expect(listeningMonthLabel('2026-10'), 'اکتبر ۲۰۲۶ (میلادی)');
  });

  test('export produces a valid full-resolution PNG', () async {
    final card = MonthlyListeningCard(
        month: '2026-10', plays: {'a': 3}, library: [track('a')]);
    final bytes = await card.renderPng();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1080);
    expect(frame.image.height, 1350);
    frame.image.dispose();
    codec.dispose();
  });

  testWidgets('empty month cannot export and a narrow screen stays usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final journey = ListeningJourney(now: () => DateTime(2026, 10, 1));
    await journey.selectAccount('alice');
    final saver = CardSaver();
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          body: ListView(children: [
        MonthlyCardSection(
            journey: journey,
            tracks: [track('آهنگی با نام بسیار طولانی برای بررسی نمایش')],
            saver: saver)
      ])),
    )));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    journey.record(track('a'));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    expect(saver.calls, 0);
    await journey.saved;
    await tester.pumpWidget(const SizedBox.shrink());
    journey.dispose();
  });
  testWidgets('preview is opt-in, failures retry and account switches hide it',
      (tester) async {
    final journey = ListeningJourney(now: () => DateTime(2026, 10, 1));
    await journey.selectAccount('alice');
    journey.record(track('a'));
    final saver = CardSaver();
    // A real PNG generated separately; widget interactions remain deterministic.
    final png = await tester.runAsync(() => MonthlyListeningCard(
        month: '2026-10', plays: {'a': 1}, library: [track('a')]).renderPng());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: MonthlyCardSection(
          journey: journey,
          tracks: [track('a')],
          saver: saver,
          renderer: (_) async => png!),
    ))));
    expect(saver.calls, 0);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('پیش‌نمایش کارت'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(saver.calls, 0);
    await tester.ensureVisible(find.text('ذخیرهٔ تصویر کارت'));
    saver.fail = true;
    await tester.tap(find.text('ذخیرهٔ تصویر کارت'));
    await tester.pumpAndSettle();
    expect(
        find.text('ذخیرهٔ کارت ناموفق بود؛ دوباره تلاش کن.'), findsOneWidget);
    saver.fail = false;
    saver.cancelled = true;
    await tester.tap(find.text('ذخیرهٔ تصویر کارت'));
    await tester.pumpAndSettle();
    expect(find.text('ذخیره لغو شد.'), findsOneWidget);
    saver.cancelled = false;
    await tester.tap(find.text('ذخیرهٔ تصویر کارت'));
    await tester.pumpAndSettle();
    expect(saver.name, 'rhythmo-2026-10.png');
    await journey.saved;
    await journey.selectAccount('bob');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('ذخیرهٔ تصویر کارت'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    journey.dispose();
  });
}
