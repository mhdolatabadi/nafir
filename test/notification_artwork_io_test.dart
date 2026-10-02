import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/features/player/data/notification_artwork_io.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('nafir_art'));
  tearDown(() async => dir.delete(recursive: true));

  ByteData bytes(List<int> values) =>
      ByteData.sublistView(Uint8List.fromList(values));

  test('the logo becomes a file: URI the notification can load', () async {
    final uri =
        await writeArtwork(Directory('${dir.path}/nested'), bytes([1, 2, 3]));

    expect(uri.scheme, 'file');
    expect(await File.fromUri(uri).readAsBytes(), [1, 2, 3]);
  });

  test('an identical copy is reused and a changed logo replaced', () async {
    final uri = await writeArtwork(dir, bytes([1, 2, 3]));
    final file = File.fromUri(uri);
    final written = await file.lastModified();

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await writeArtwork(dir, bytes([1, 2, 3]));
    expect(await file.lastModified(), written);

    await writeArtwork(dir, bytes([4, 5, 6, 7]));
    expect(await file.readAsBytes(), [4, 5, 6, 7]);
  });

  test('the bundled logo asset exists', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final logo = await rootBundle.load('assets/icon/nafir.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });
}
