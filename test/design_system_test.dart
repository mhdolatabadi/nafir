import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/core/design/design.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/features/debug/presentation/design_gallery.dart';

/// WCAG contrast ratio of [fg] over [bg], blending a translucent [bg] onto
/// the app background first.
double contrast(Color fg, Color bg) {
  final opaque = Color.alphaBlend(bg, NafirColors.background);
  final a = Color.alphaBlend(fg, opaque).computeLuminance();
  final b = opaque.computeLuminance();
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

Widget _app(Widget home, {bool reduceMotion = false}) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: home,
    );

/// Files that still hold raw values, by kind. Each screen pass empties its
/// files out of these lists; the test fails when a listed file is already
/// clean, so the lists only ever shrink.
const _rawColourFiles = {
  'lib/features/library/presentation/library_screen.dart',
  'lib/features/library/presentation/track_metadata_editor.dart',
  'lib/features/player/presentation/now_playing_screen.dart',
  'lib/features/playlists/presentation/playlists_screen.dart',
};
const _rawRadiusFiles = {
  'lib/core/widgets/app_loading_screen.dart',
  'lib/features/history/presentation/recently_played_shelf.dart',
  'lib/features/identify/presentation/identify_screen.dart',
  'lib/features/library/presentation/library_screen.dart',
  'lib/features/lyrics/presentation/lyrics_sheet.dart',
  'lib/features/player/presentation/mini_player.dart',
  'lib/features/player/presentation/now_playing_screen.dart',
  'lib/features/playlists/presentation/playlists_screen.dart',
  'lib/features/playlists/presentation/popular_playlists_screen.dart',
  'lib/features/playlists/presentation/shared_playlist_screen.dart',
  'lib/features/settings/presentation/storage_usage_card.dart',
};
const _rawDurationFiles = {
  'lib/features/identify/presentation/identify_screen.dart',
  'lib/features/library/presentation/track_metadata_editor.dart',
  'lib/features/lyrics/presentation/lyrics_sheet.dart',
  'lib/features/player/presentation/now_playing_screen.dart',
};

void main() {
  group('tokens', () {
    test('text meets WCAG AA on every surface it is used on', () {
      const surfaces = [
        NafirColors.background,
        NafirColors.surface,
        NafirColors.surfaceStrong,
        NafirColors.surfaceRaised,
        NafirColors.containerHigh,
        NafirColors.card,
        NafirColors.overlay,
        NafirColors.field,
      ];
      for (final surface in surfaces) {
        for (final text in [
          NafirColors.onSurface,
          NafirColors.onSurfaceVariant,
        ]) {
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5),
              reason: '$text on $surface');
        }
        // The accent and outlines are UI marks: 3:1.
        expect(contrast(NafirColors.primary, surface), greaterThanOrEqualTo(3));
        expect(contrast(NafirColors.outline, surface), greaterThanOrEqualTo(3));
      }
      expect(contrast(NafirColors.onPrimary, NafirColors.primary),
          greaterThanOrEqualTo(4.5));
      expect(
          contrast(
              NafirColors.onPrimaryContainer, NafirColors.primaryContainer),
          greaterThanOrEqualTo(4.5));
      expect(
          contrast(
              NafirColors.onSecondaryContainer, NafirColors.secondaryContainer),
          greaterThanOrEqualTo(4.5));
      for (var i = 0; i < 360; i += 15) {
        // Light text stays readable on every artwork tint.
        expect(contrast(NafirColors.onSurfaceVariant, artworkTint('seed-$i')),
            greaterThanOrEqualTo(4.5));
      }
    });

    test('the theme carries the tokens and the Vazirmatn scale', () {
      final theme = NafirTheme.dark();
      expect(theme.extension<NafirTokens>(), isNotNull);
      expect(theme.textTheme.bodyLarge?.fontFamily, NafirType.family);
      expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w800);
      expect(theme.colorScheme.primary, NafirColors.primary);
      expect(artworkTint('a'), artworkTint('a'));
    });

    testWidgets('motion collapses under reduce-motion', (tester) async {
      late Duration normal, reduced;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        normal = NafirMotion.of(context, NafirMotion.medium);
        return const SizedBox();
      })));
      await tester.pumpWidget(_app(Builder(builder: (context) {
        reduced = NafirMotion.of(context, NafirMotion.medium);
        return const SizedBox();
      }), reduceMotion: true));
      expect(normal, NafirMotion.medium);
      expect(reduced, Duration.zero);
    });

    test('every button shows a 2 px focus ring', () {
      final theme = NafirTheme.dark();
      for (final style in [
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        final focused = style!.side!.resolve({WidgetState.focused});
        expect(focused?.width, 2);
        expect(focused?.color, NafirColors.primary);
      }
    });
  });

  group('raw values stay in the token file', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('lib/core/design/tokens.dart'))
        .toList();

    void check(String what, RegExp pattern, Set<String> allowed,
        {bool Function(String path)? scope}) {
      final offenders = <String>{
        for (final file in files)
          if ((scope?.call(file.path) ?? true) &&
              pattern.hasMatch(file.readAsStringSync()))
            file.path,
      };
      expect(offenders.difference(allowed), isEmpty,
          reason: 'raw $what: use the tokens in lib/core/design/tokens.dart');
      expect(allowed.difference(offenders), isEmpty,
          reason: 'already migrated: remove these from the $what allowlist');
    }

    test('colours', () {
      check(
        'colours',
        RegExp(r'Color\(0x|(?<![A-Za-z])Colors\.(?!transparent\b)[a-z]'),
        _rawColourFiles,
      );
    });

    test('radii', () {
      check('radii', RegExp(r'Radius\.circular\(\d'), _rawRadiusFiles);
    });

    test('animation durations in UI code', () {
      check(
        'durations',
        RegExp(r'Duration\(milliseconds: \d'),
        _rawDurationFiles,
        scope: (path) =>
            path.contains('/presentation/') ||
            path.contains('lib/core/') ||
            path.contains('lib/app/'),
      );
    });
  });

  group('components', () {
    testWidgets('a state view has a title, message and a 48 px action',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(_app(Scaffold(
        body: NafirStateView.error(
          icon: NafirIcons.cloudSlash,
          title: 'دریافت نشد',
          message: 'دوباره تلاش کنید.',
          action: FilledButton(
            onPressed: () => retried = true,
            child: const Text('تلاش دوباره'),
          ),
        ),
      )));
      expect(find.text('دریافت نشد'), findsOneWidget);
      expect(find.text('دوباره تلاش کنید.'), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48));
      await tester.tap(find.text('تلاش دوباره'));
      expect(retried, isTrue);

      await tester.pumpWidget(_app(const Scaffold(
        body: NafirStateView.loading(title: 'در حال بارگذاری…'),
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('در حال بارگذاری…'), findsOneWidget);
    });

    testWidgets('a track row truncates long titles and stays 64 px tall',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Scaffold(
        body: ListView(children: [
          NafirTrackRow(
            seed: 'x',
            title:
                'یک عنوان بسیار بسیار بلند که هرگز در یک خط جا نمی‌شود و ادامه دارد',
            subtitle: 'هنرمند',
            detail: '۳ مگابایت',
            onTap: () {},
          ),
        ]),
      )));
      expect(tester.takeException(), isNull);
      final row = tester.getRect(find.byType(NafirTrackRow));
      expect(row.height, greaterThanOrEqualTo(64));
      expect(find.text('هنرمند · ۳ مگابایت'), findsOneWidget);
    });

    testWidgets('confirming asks with a safe default', (tester) async {
      bool? answer;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer = await showNafirConfirm(
              context,
              title: 'حذف؟',
              confirmLabel: 'حذف',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });

  group('gallery', () {
    for (final size in const [Size(360, 740), Size(1280, 900)]) {
      testWidgets('shows every token and component at ${size.width.toInt()} px',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(const DesignGallery()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no overflow');

        final list = find.byType(Scrollable).first;
        for (final heading in [
          'رنگ‌ها',
          'حروف',
          'دکمه‌ها',
          'ردیف آهنگ',
          'حالت‌ها',
          'برگه و گفت‌وگو',
        ]) {
          await tester.scrollUntilVisible(find.text(heading), 200,
              scrollable: list);
          expect(tester.takeException(), isNull, reason: heading);
          if (heading == 'دکمه‌ها') {
            for (final tooltip in ['نمونه', 'پخش']) {
              await tester.scrollUntilVisible(find.byTooltip(tooltip), 100,
                  scrollable: list);
              final target = tester.getSize(find.byTooltip(tooltip));
              expect(target.width, greaterThanOrEqualTo(48));
              expect(target.height, greaterThanOrEqualTo(48));
            }
          }
        }
        // Content stays in a centred column on desktop.
        final page = tester.getRect(find.byType(ListView).first);
        expect(page.width, lessThanOrEqualTo(NafirSpace.pageWidth));
        if (size.width > NafirSpace.pageWidth) {
          expect(page.left, greaterThan(0));
        }

        // The sheet's last row clears the gesture bar.
        await tester.scrollUntilVisible(find.text('باز کردن برگه'), 200,
            scrollable: list);
        await tester.tap(find.text('باز کردن برگه'));
        // The loading state's spinner never settles: pump through the
        // sheet's entrance instead.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final sheetList = find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable));
        await tester.scrollUntilVisible(find.text('آهنگ ۱۲'), 200,
            scrollable: sheetList);
        await tester.drag(sheetList, const Offset(0, -400));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.getRect(find.text('آهنگ ۱۲')).bottom,
            lessThanOrEqualTo(size.height - 34));
      });
    }
  });
}
