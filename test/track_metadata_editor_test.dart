import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/app/app_theme.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/library/data/track_metadata.dart';
import 'package:nafir/features/library/presentation/track_metadata_editor.dart';

const _track = Track(
  id: 't1',
  title: 'عنوان قدیمی',
  artist: 'خواننده',
  contentType: 'audio/mpeg',
  sizeBytes: 1000,
  fileName: 'آهنگ قدیمی.mp3',
  year: 2020,
  version: 3,
);

/// Records saves and answers with [answer].
class _Saves {
  _Saves([this.answer]);

  FutureOr<MetadataSaveResult> Function(TrackMetadataDraft, int)? answer;
  final calls = <(TrackMetadataDraft, int)>[];

  Future<MetadataSaveResult> call(TrackMetadataDraft draft, int version) async {
    calls.add((draft, version));
    return await (answer?.call(draft, version) ??
        MetadataSaved(Track(
          id: 't1',
          title: draft.title.trim(),
          contentType: 'audio/mpeg',
          sizeBytes: 1000,
          fileName: draft.fileName,
          version: version + 1,
        )));
  }
}

/// Opens the editor from a launcher page, like the library does, and keeps
/// what it returned.
class _Host {
  Track? result;
  bool closed = false;
}

Future<_Host> _open(
  WidgetTester tester,
  _Saves saves, {
  Track track = _track,
  EdgeInsets padding = EdgeInsets.zero,
  bool settle = true,
}) async {
  final host = _Host();
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: NafirTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: padding),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              host.result = await showTrackMetadataEditor(context,
                  track: track, onSave: saves.call);
              host.closed = true;
            },
            child: const Text('باز کردن'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('باز کردن'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A progress indicator never settles; let the route transition finish.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return host;
}

Finder _field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));

Finder get _save => find.byKey(const ValueKey('save'));

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_save).onPressed != null;

final _list = find
    .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable))
    .first;

/// Scrolls the lazily built form until the [key] field is on screen.
Future<void> _show(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 120,
      scrollable: _list);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await _show(tester, key);
  await tester.enterText(_field(key), text);
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(_save);
  await tester.pump();
}

void main() {
  testWidgets(
      'fits a 360 px phone: no overflow, 48 px save, nothing hidden behind it',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
      tester,
      _Saves(),
      track: const Track(
        id: 't1',
        title: 'یک عنوان بسیار بسیار طولانی فارسی با چند واژهٔ Latin در میانه',
        contentType: 'audio/flac',
        sizeBytes: 1,
        fileName: 'نام فایلی بسیار طولانی که باید بدون سرریز جا شود.flac',
      ),
      padding: const EdgeInsets.only(bottom: 48),
    );
    expect(tester.takeException(), isNull);

    final save = tester.getRect(_save);
    expect(save.height, greaterThanOrEqualTo(48));
    expect(save.left, greaterThanOrEqualTo(0));
    expect(save.right, lessThanOrEqualTo(360));
    // The save bar sits above the system navigation inset.
    expect(save.bottom, lessThanOrEqualTo(640 - 48));

    // Scrolled to the end, the last field ends above the save bar.
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    final comment = tester.getRect(find.byKey(const ValueKey('comment')));
    expect(comment.bottom, lessThanOrEqualTo(save.top));
    for (final key in ['year', 'trackNumber', 'discNumber']) {
      await _show(tester, key);
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('pre-fills the track, keeps the extension and saves the version',
      (tester) async {
    final saves = _Saves();
    final host = await _open(tester, saves);

    expect(find.text('آهنگ قدیمی'), findsOneWidget); // file name without .mp3
    expect(find.text('.mp3'), findsOneWidget);
    expect(find.text('عنوان قدیمی'), findsOneWidget);
    await _show(tester, 'year');
    expect(find.text('2020'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse, reason: 'nothing changed yet');

    await _type(tester, 'fileName', 'آهنگ تازه');
    await _type(tester, 'title', 'عنوان تازه');
    await _type(tester, 'artist', ''); // clearing a field
    await _type(tester, 'year', '۱۴۰۳'); // Persian digits are accepted
    expect(_saveEnabled(tester), isTrue);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final (draft, version) = saves.calls.single;
    expect(version, 3);
    expect(draft.fileName, 'آهنگ تازه.mp3');
    expect(draft.title, 'عنوان تازه');
    expect(draft.artist, '');
    expect(draft.year, 1403);
    expect(host.closed, isTrue);
    expect(host.result?.title, 'عنوان تازه');
  });

  testWidgets('catches bad input locally before calling the server',
      (tester) async {
    final saves = _Saves();
    await _open(tester, saves);

    await _type(tester, 'title', '   ');
    await _type(tester, 'fileName', 'پوشه/آهنگ');
    await _type(tester, 'trackNumber', '0');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(saves.calls, isEmpty);
    expect(find.text('این مورد نباید خالی باشد.'), findsOneWidget);
    expect(find.textContaining('این نویسه‌ها مجاز نیستند'), findsOneWidget);
    await _show(tester, 'trackNumber');
    expect(find.text('عددی بین 1 و 999 وارد کن.'), findsOneWidget);
  });

  testWidgets('a second tap while saving does not save twice', (tester) async {
    final pending = Completer<MetadataSaveResult>();
    final saves = _Saves((_, __) => pending.future);
    final host = await _open(tester, saves);

    await _type(tester, 'title', 'تازه');
    await _tapSave(tester);
    await _tapSave(tester);
    expect(find.text('در حال ذخیره…'), findsOneWidget);
    expect(saves.calls, hasLength(1));

    // Leaving is blocked while saving.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(host.closed, isFalse);

    pending.complete(const MetadataSaveFailed());
    await tester.pumpAndSettle();
    expect(find.textContaining('ذخیره نشد'), findsOneWidget);
    expect(host.closed, isFalse);
  });

  testWidgets('a conflict offers the newer copy or keeping my changes',
      (tester) async {
    const latest = Track(
      id: 't1',
      title: 'عنوان از دستگاه دیگر',
      contentType: 'audio/mpeg',
      sizeBytes: 1000,
      fileName: 'آهنگ قدیمی.mp3',
      version: 5,
    );
    final saves = _Saves((_, __) => const MetadataConflict(latest));
    await _open(tester, saves);

    await _type(tester, 'title', 'عنوان من');
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conflict')), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);

    // Keep mine: my text stays and the next save is based on version 5.
    await tester.tap(find.text('نگه‌داشتن تغییرات من'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conflict')), findsNothing);
    expect(find.text('عنوان من'), findsOneWidget);
    saves.answer = null;
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(saves.calls.last.$2, 5);
  });

  testWidgets('showing the newer copy replaces the form and clears changes',
      (tester) async {
    const latest = Track(
      id: 't1',
      title: 'عنوان از دستگاه دیگر',
      contentType: 'audio/mpeg',
      sizeBytes: 1000,
      fileName: 'نام تازه.mp3',
      version: 5,
    );
    final saves = _Saves((_, __) => const MetadataConflict(latest));
    final host = await _open(tester, saves);

    await _type(tester, 'title', 'عنوان من');
    await _tapSave(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش نسخهٔ تازه'));
    await tester.pumpAndSettle();

    expect(find.text('عنوان از دستگاه دیگر'), findsOneWidget);
    expect(find.text('نام تازه'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
    // Nothing unsaved, so closing needs no confirmation.
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(host.closed, isTrue);
    expect(host.result, isNull);
  });

  testWidgets('a field the server rejects is marked on that field',
      (tester) async {
    final saves = _Saves((_, __) => const MetadataInvalid('fileName'));
    await _open(tester, saves);

    await _type(tester, 'fileName', 'نام');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('سرور این مقدار را نپذیرفت؛ آن را اصلاح کن.'),
        findsOneWidget);
    // Editing the field clears the server's complaint.
    await _type(tester, 'fileName', 'نام دیگر');
    await tester.pumpAndSettle(); // the old message fades out
    expect(
        find.text('سرور این مقدار را نپذیرفت؛ آن را اصلاح کن.'), findsNothing);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    final host = await _open(tester, _Saves());
    await _type(tester, 'title', 'تغییر');

    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.text('تغییرات ذخیره نشده‌اند'), findsOneWidget);
    await tester.tap(find.text('ادامهٔ ویرایش'));
    await tester.pumpAndSettle();
    expect(host.closed, isFalse);
    expect(find.text('تغییر'), findsOneWidget);

    // The system back gesture asks too.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('دور ریختن تغییرات'));
    await tester.pumpAndSettle();
    expect(host.closed, isTrue);
    expect(host.result, isNull);
  });

  testWidgets('says honestly when the file itself cannot carry the tags',
      (tester) async {
    await _open(
      tester,
      _Saves(),
      track: const Track(
        id: 't1',
        title: 'M4A',
        contentType: 'audio/mp4',
        sizeBytes: 1,
        fileName: 'song.m4a',
        embeddedTags: EmbeddedTags(
          status: EmbeddedTagStatus.unsupported,
          unsupportedFields: ['title', 'artist'],
        ),
      ),
    );
    expect(find.textContaining('فایل‌های M4A برچسب داخلی'), findsOneWidget);
  });

  testWidgets('shows when the file is still being updated', (tester) async {
    await _open(
      tester,
      _Saves(),
      track: const Track(
        id: 't1',
        title: 'T',
        contentType: 'audio/mpeg',
        sizeBytes: 1,
        fileName: 'a.mp3',
        embeddedTags: EmbeddedTags(status: EmbeddedTagStatus.pending),
      ),
      settle: false,
    );
    expect(find.textContaining('در حال نوشتن در خود فایل'), findsOneWidget);
  });

  test('text direction follows the first strong letter', () {
    expect(directionOf(''), TextDirection.rtl);
    expect(directionOf('آهنگ Song'), TextDirection.rtl);
    expect(directionOf('Song آهنگ'), TextDirection.ltr);
    expect(directionOf('2024 Mix'), TextDirection.ltr);
    expect(directionOf('۱۴۰۳'), TextDirection.rtl);
  });
}
