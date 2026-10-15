import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/presentation/playlists_screen.dart';
import 'package:nafir/features/playlists/presentation/popular_playlists_screen.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'playlist_sharing_test.dart'
    show FakePlaylistsApi, listed, sharedMix, token;
import 'upload_controller_test.dart' show FakeTracksApi;

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: home,
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
}

void _expectTarget(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48), reason: '$finder');
  expect(size.height, greaterThanOrEqualTo(48), reason: '$finder');
}

void main() {
  for (final (size, columns) in const [
    (Size(360, 740), 2),
    (Size(1280, 900), 4),
  ]) {
    final label = '${size.width.toInt()} px';

    testWidgets(
        'a grid of ranked square tiles, with no owner email, '
        'at $label', (tester) async {
      _size(tester, size);
      final long = 'فهرستی با اسمی بسیار بسیار طولانی که نباید بیرون بزند';
      final api = FakePlaylistsApi()
        ..shared[token] = sharedMix()
        ..public = [
          listed('loved', likes: 5),
          for (var i = 2; i <= 12; i++)
            listed('$long $i', likes: 100 - i, shareToken: '$i'.padLeft(22)),
        ];
      final tracks = FakeTracksApi();
      final player = PlayerController(
          api: tracks, engine: FakeAudioEngine(), token: () => 'tok');
      await tester.pumpWidget(_app(PopularPlaylistsScreen(
        controller: PlaylistsController(api: api, token: () => 'tok'),
        player: player,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow');

      // Owners stay private.
      expect(find.textContaining('@'), findsNothing);

      // Ranked, square covers, the given number of columns.
      expect(find.text(persianDigits(1)), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^رتبهٔ ۱: loved')), findsOneWidget);
      final first = tester.getRect(find.bySemanticsLabel(RegExp('^رتبهٔ ۱:')));
      expect(first.width, closeTo(first.height, 0.5));
      final second = tester.getRect(find.bySemanticsLabel(RegExp('^رتبهٔ ۲:')));
      expect(second.top, first.top, reason: 'rank 2 shares the first row');
      final rowStart = find
          .bySemanticsLabel(RegExp('^رتبهٔ ${persianDigits(columns + 1)}:'));
      expect(tester.getRect(rowStart).top, greaterThan(first.bottom),
          reason: '$columns tiles a row');
      // Inside the gutter, and centred on desktop.
      expect(first.right, lessThanOrEqualTo(size.width - 16));
      if (size.width > 960) {
        expect(first.right, lessThan(size.width - 100));
      }

      // Play and like are 48 px targets that work.
      final play = find.byTooltip('پخش loved');
      _expectTarget(tester, play);
      _expectTarget(tester, find.widgetWithText(TextButton, '۵'));
      await tester.tap(find.widgetWithText(TextButton, '۵'));
      await tester.pumpAndSettle();
      expect(api.likeCalls, [true]);
      expect(find.byIcon(NafirIcons.heartFill), findsOneWidget);

      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tracks.calls, contains('shared:$token:s1'));
      expect(player.track?.title, 'Their song');

      // With the mini player up, the last tile still scrolls clear of it.
      final last = find.bySemanticsLabel(RegExp('^رتبهٔ ۱۲:'));
      await tester.scrollUntilVisible(last, 300,
          scrollable: find.byType(Scrollable).last);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 600));
      final lastTileBottom = tester.getRect(last).bottom + 56;
      final mini = tester.getRect(find.byTooltip('توقف').first);
      expect(lastTileBottom, lessThanOrEqualTo(mini.top),
          reason: 'title and like row end above the mini player');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the playlists tab leads with a popular entry at $label',
        (tester) async {
      _size(tester, size);
      var opened = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width > 900 ? 900 : size.width,
            child: PopularPlaylistsEntry(onOpen: () => opened++),
          ),
        ),
      )));
      expect(tester.takeException(), isNull);
      final entry = find.byType(PopularPlaylistsEntry);
      expect(tester.getSize(entry).height, greaterThanOrEqualTo(72));
      expect(find.text('فهرست‌های پخش محبوب'), findsOneWidget);
      await tester.tap(entry);
      expect(opened, 1);
    });
  }
}
