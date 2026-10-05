import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/api/api_client.dart';
import 'package:nafir/features/auth/data/token_store.dart';
import 'package:nafir/features/library/data/local_audio_library.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/main.dart';

import 'cache_controller_test.dart' show FakeAudioCache;
import 'library_sync_controller_test.dart' show FakeUploadSource;
import 'local_audio_controller_test.dart' show FakeLocalAudioLibrary;
import 'player_controller_test.dart' show FakeAudioEngine;
import 'upload_controller_test.dart' show FakeTracksApi, FakeUploader;
import 'widget_test.dart' show FakeAuthApi, FakePicker;

Track _device(int id, String title, {int size = 4, String? fileName}) => Track(
      id: 'device:$id',
      title: title,
      contentType: 'audio/mpeg',
      sizeBytes: size,
      fileName: fileName ?? '$title.mp3',
      sourceUri: Uri.parse('content://media/external/audio/media/$id'),
    );

Future<void> _pump(
  WidgetTester tester, {
  required FakeTracksApi tracks,
  required FakeLocalAudioLibrary device,
  FakeUploader? uploader,
  FakeUploadSource? source,
}) async {
  await tester.pumpWidget(NafirApp(
    healthCheck: () async {},
    authApi: FakeAuthApi(),
    tokenStore: MemoryTokenStore('valid-token'),
    tracksApi: tracks,
    audioEngine: FakeAudioEngine(),
    audioCache: FakeAudioCache(),
    uploader: uploader ?? FakeUploader(),
    picker: FakePicker(null),
    localAudioLibrary: device,
    localAudioUpload: source ?? FakeUploadSource(),
  ));
  await tester.pumpAndSettle();
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
      of: _row(title), matching: find.byTooltip('اقدامات آهنگ')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('device, server and synced tracks appear once with badges',
      (tester) async {
    await _pump(
      tester,
      tracks: FakeTracksApi([
        const Track(
            id: 't1',
            title: 'Server only',
            contentType: 'audio/mpeg',
            sizeBytes: 100,
            fileName: 'Server_only.mp3'),
        const Track(
            id: 't2',
            title: 'Both',
            contentType: 'audio/mpeg',
            sizeBytes: 200,
            fileName: 'Both.mp3'),
      ]),
      device: FakeLocalAudioLibrary(LocalAudioResult(LocalAudioStatus.loaded, [
        _device(1, 'Both', size: 200),
        _device(2, 'Phone only', size: 300),
      ])),
    );

    expect(find.text('۳ آهنگ'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);
    expect(
        find.descendant(
            of: _row('Server only'), matching: find.byTooltip('روی سرور')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _row('Both'), matching: find.byTooltip('روی دستگاه و سرور')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _row('Phone only'), matching: find.byTooltip('فقط روی دستگاه')),
        findsOneWidget);

    await _openMenu(tester, 'Both');
    expect(find.text('حذف از دستگاه'), findsOneWidget);
    expect(find.text('حذف از سرور'), findsOneWidget);
    expect(find.text('ویرایش اطلاعات آهنگ'), findsOneWidget);
    expect(find.text('آپلود به سرور'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _openMenu(tester, 'Phone only');
    expect(find.text('آپلود به سرور'), findsOneWidget);
    expect(find.text('حذف از دستگاه'), findsOneWidget);
    expect(find.text('حذف از سرور'), findsNothing);
    expect(find.text('ویرایش اطلاعات آهنگ'), findsNothing);
  });

  testWidgets('uploading from the menu shows progress, cancels, then syncs',
      (tester) async {
    final uploader = FakeUploader()..stall = true;
    final tracks = FakeTracksApi();
    // The fake server names the uploaded track «Song», 4 bytes.
    await _pump(
      tester,
      tracks: tracks,
      uploader: uploader,
      device: FakeLocalAudioLibrary(
          LocalAudioResult(LocalAudioStatus.loaded, [_device(1, 'Song')])),
    );

    await _openMenu(tester, 'Song');
    await tester.tap(find.text('آپلود به سرور'));
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('در حال آپلود'), findsOneWidget);
    expect(find.textContaining('در حال آپلود ۵۰٪'), findsOneWidget);

    await _openMenu(tester, 'Song');
    await tester.tap(find.text('لغو آپلود'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('فقط روی دستگاه'), findsOneWidget);
    expect(tracks.deleted, ['t1']);

    uploader.stall = false;
    await _openMenu(tester, 'Song');
    await tester.tap(find.text('آپلود به سرور'));
    await tester.pumpAndSettle();

    expect(find.text('Song'), findsOneWidget);
    expect(find.byTooltip('روی دستگاه و سرور'), findsOneWidget);
    expect(find.text('«Song» روی سرور آپلود شد.'), findsOneWidget);
  });

  testWidgets('a failed upload explains why and can be retried',
      (tester) async {
    final tracks = FakeTracksApi()
      ..createError =
          const ApiException('quota', statusCode: 413, code: 'quota_exceeded');
    await _pump(
      tester,
      tracks: tracks,
      device: FakeLocalAudioLibrary(
          LocalAudioResult(LocalAudioStatus.loaded, [_device(1, 'Song')])),
    );

    await _openMenu(tester, 'Song');
    await tester.tap(find.text('آپلود به سرور'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('آپلود ناموفق'), findsOneWidget);
    expect(
        find.descendant(
            of: _row('Song'), matching: find.textContaining('فضای ابری')),
        findsOneWidget);

    tracks.createError = null;
    await _openMenu(tester, 'Song');
    await tester.tap(find.text('تلاش دوباره برای آپلود'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('روی دستگاه و سرور'), findsOneWidget);
  });

  testWidgets('removing a synced track from the device keeps the server copy',
      (tester) async {
    final device = FakeLocalAudioLibrary(
        LocalAudioResult(LocalAudioStatus.loaded, [_device(1, 'Song')]));
    await _pump(
      tester,
      tracks: FakeTracksApi(const [
        Track(
            id: 't1',
            title: 'Song',
            contentType: 'audio/mpeg',
            sizeBytes: 4,
            fileName: 'Song.mp3'),
      ]),
      device: device,
    );

    await _openMenu(tester, 'Song');
    await tester.tap(find.text('حذف از دستگاه'));
    await tester.pumpAndSettle();
    expect(find.textContaining('نسخهٔ سرور می‌ماند'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف از دستگاه'));
    await tester.pumpAndSettle();

    expect(
        device.deleted, [Uri.parse('content://media/external/audio/media/1')]);
    expect(find.text('Song'), findsOneWidget);
    expect(find.byTooltip('روی سرور'), findsOneWidget);
  });

  testWidgets(
      'on a 360 px phone, sync progress and the mini player never cover '
      'the last track', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final uploader = FakeUploader()..stall = true;
    await _pump(
      tester,
      uploader: uploader,
      tracks: FakeTracksApi([
        for (var i = 0; i < 12; i++)
          Track(
            id: 's$i',
            title: 'یک عنوان خیلی طولانی برای آهنگ سرور شمارهٔ $i',
            contentType: 'audio/mpeg',
            sizeBytes: 10 + i,
          ),
      ]),
      device: FakeLocalAudioLibrary(LocalAudioResult(LocalAudioStatus.loaded, [
        for (var i = 0; i < 12; i++)
          _device(i, 'Device track with a very long Latin title $i',
              size: 100 + i),
      ])),
    );

    // Play something so the mini player shows, and start an upload so the
    // upload card and a progress row show too.
    await tester.tap(find.text('یک عنوان خیلی طولانی برای آهنگ سرور شمارهٔ 0'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 14; i++) {
      await tester.drag(find.byType(TabBarView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    // Upload the last track, so its row shows progress at the very end.
    await _openMenu(tester, 'Device track with a very long Latin title 11');
    await tester.tap(find.text('آپلود به سرور'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The upload card grows above the list; scroll to the end again.
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(TabBarView), const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byTooltip('در حال آپلود'), findsOneWidget);
    expect(find.textContaining('در حال آپلود ۵۰٪'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final lastTitle = find.text('Device track with a very long Latin title 11');
    final lastRow =
        tester.getRect(_row('Device track with a very long Latin title 11'));
    expect(lastTitle, findsOneWidget);
    final miniPlayerTop = tester.getTopLeft(find.byTooltip('توقف')).dy - 16;
    expect(lastRow.bottom, lessThan(miniPlayerTop));
    // The add-music button is lifted above the mini player, never over it.
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.bottom, lessThanOrEqualTo(miniPlayerTop + 16));
    expect(tester.takeException(), isNull);
  });
}
