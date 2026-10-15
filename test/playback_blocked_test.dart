import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/data/audio_engine.dart';
import 'package:nafir/features/player/presentation/mini_player.dart';

import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi;

const _track = Track(
    id: 'a',
    title: 'آهنگ',
    artist: 'خواننده',
    contentType: 'audio/mpeg',
    sizeBytes: 1);

void main() {
  test('browser autoplay refusals are recognised', () {
    expect(
        PlaybackBlocked.matches(Exception(
            "NotAllowedError: play() failed because the user didn't interact "
            'with the document first.')),
        isTrue);
    expect(
        PlaybackBlocked.matches(Exception(
            'NotAllowedError: The request is not allowed by the user agent')),
        isTrue);
    expect(PlaybackBlocked.matches(Exception('Source error 404')), isFalse);
    expect(PlaybackBlocked.matches(const PlaybackBlocked()), isFalse);
  });

  test('a blocked start waits for a tap instead of failing or retrying',
      () async {
    final engine = FakeAudioEngine();
    final api = FakeTracksApi();
    final player =
        PlayerController(api: api, engine: engine, token: () => 'tok');
    addTearDown(player.dispose);
    await player.playFrom(const [_track], 0);
    await pumpEventQueue();
    final loads = engine.loads.length;

    // The browser refused: the engine stops and reports it.
    engine.playingCtl.add(false);
    engine.errorCtl.add(const PlaybackBlocked());
    await pumpEventQueue();
    expect(player.needsTap, isTrue);
    expect(player.status, PlayerStatus.paused);
    expect(engine.loads.length, loads, reason: 'the link is fine; no reload');

    await player.resume();
    await pumpEventQueue();
    expect(player.needsTap, isFalse);
    expect(player.status, PlayerStatus.playing);
  });

  testWidgets('the mini player asks for a tap on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = FakeAudioEngine();
    final player = PlayerController(
        api: FakeTracksApi(), engine: engine, token: () => 't');
    addTearDown(player.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: NafirTheme.dark(),
      home: Scaffold(bottomNavigationBar: MiniPlayer(player: player)),
    ));
    await tester.runAsync(() => player.playFrom(const [_track], 0));
    engine.playingCtl.add(false);
    engine.errorCtl.add(const PlaybackBlocked());
    await tester.pump();

    expect(find.text('برای پخش، دکمه‌ی پخش را بزن.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('پخش'));
    await tester.pump();
    expect(find.text('برای پخش، دکمه‌ی پخش را بزن.'), findsNothing);
    expect(find.text('خواننده'), findsOneWidget);
  });
}
