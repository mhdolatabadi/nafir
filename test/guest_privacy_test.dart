import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/features/auth/application/auth_controller.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/auth/presentation/sign_in_screen.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/presentation/popular_playlists_screen.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'playlist_sharing_test.dart' show FakePlaylistsApi;
import 'upload_controller_test.dart' show FakeTracksApi;
import 'widget_test.dart' show FakeAuthApi;

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: home,
    );

Uri? _site(String path) => Uri.parse('https://rhythmo.example').resolve(path);

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('a guest reads the privacy policy without signing in', () {
    Widget guestHome(List<Uri> opened, {bool opens = true}) =>
        PopularPlaylistsScreen(
          controller:
              PlaylistsController(api: FakePlaylistsApi(), token: () => null),
          player: PlayerController(
              api: FakeTracksApi(),
              engine: FakeAudioEngine(),
              token: () => null),
          onSignIn: () {},
          siteUri: _site,
          openLink: (uri) async {
            opened.add(uri);
            return opens;
          },
        );

    testWidgets('from the guest home, on a narrow screen', (tester) async {
      _narrow(tester);
      final opened = <Uri>[];
      await tester.pumpWidget(_app(guestHome(opened)));
      await tester.pumpAndSettle();

      final privacy = find.byTooltip('حریم خصوصی');
      expect(privacy, findsOneWidget);
      final size = tester.getSize(privacy);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // Sign-in stays reachable next to it.
      expect(find.text('ورود / ثبت‌نام'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(privacy);
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://rhythmo.example/privacy')]);
    });

    testWidgets('says so when the page cannot open', (tester) async {
      await tester.pumpWidget(_app(guestHome([], opens: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('حریم خصوصی'));
      await tester.pumpAndSettle();
      expect(find.text('باز کردن صفحه ممکن نشد.'), findsOneWidget);
    });

    testWidgets('from the sign-in screen, on a narrow screen', (tester) async {
      _narrow(tester);
      final opened = <Uri>[];
      await tester.pumpWidget(_app(SignInScreen(
        controller:
            AuthController(api: FakeAuthApi(), tokenStore: MemoryTokenStore()),
        siteUri: _site,
        openLink: (uri) async {
          opened.add(uri);
          return true;
        },
      )));
      await tester.pumpAndSettle();

      final privacy = find.ancestor(
          of: find.text('حریم خصوصی'),
          matching: find.bySubtype<ButtonStyleButton>());
      expect(privacy, findsOneWidget);
      expect(tester.getSize(privacy).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(privacy);
      await tester.tap(privacy);
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://rhythmo.example/privacy')]);
    });
  });
}
