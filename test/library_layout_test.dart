import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/design/design.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/main.dart';

import 'cache_controller_test.dart' show FakeAudioCache;
import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi, FakeUploader;
import 'widget_test.dart' show FakeAuthApi, FakePicker;

Future<void> _pump(WidgetTester tester, Size size, List<Track> tracks) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(NafirApp(
    healthCheck: () async {},
    authApi: FakeAuthApi(),
    tokenStore: MemoryTokenStore('valid-token'),
    tracksApi: FakeTracksApi(tracks),
    audioEngine: FakeAudioEngine(),
    audioCache: FakeAudioCache(),
    uploader: FakeUploader(),
    picker: FakePicker(null),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(360, 740), Size(1280, 900)]) {
    final label = '${size.width.toInt()} px';

    testWidgets('an empty library says what to do at $label', (tester) async {
      await _pump(tester, size, const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(NafirStateView), findsWidgets);
      expect(find.text('کتابخانهٔ شما خالی است'), findsOneWidget);
    });

    testWidgets('the mini player never covers the last track at $label',
        (tester) async {
      final tracks = [
        for (var i = 1; i <= 30; i++)
          Track(
            id: 't$i',
            title: 'آهنگ شمارهٔ $i با عنوانی که شاید طولانی باشد',
            artist: 'هنرمند',
            contentType: 'audio/mpeg',
            sizeBytes: 1024 * 1024,
          ),
      ];
      await _pump(tester, size, tracks);
      await tester.tap(find.text(tracks.first.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final last = find.text(tracks.last.title);
      final list = find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .last;
      await tester.dragUntilVisible(last, list, const Offset(0, -300));
      await tester.drag(list, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      final mini = tester.getRect(find.byTooltip('توقف').first);
      final row = tester.getRect(last);
      expect(row.bottom, lessThanOrEqualTo(mini.top),
          reason: 'the last row ends above the mini player');
      if (size.width > NafirSpace.pageWidth) {
        // Desktop content keeps away from the window edges.
        expect(row.left, greaterThan(NafirSpace.lg));
      }
    });
  }
}
