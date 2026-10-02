import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nafir/features/player/data/notification_artwork.dart';
import 'package:path_provider/path_provider.dart';

Future<Uri?> resolveArtwork() async {
  try {
    final directory = await getApplicationSupportDirectory();
    final bytes = await rootBundle.load(notificationArtworkAsset);
    return await writeArtwork(directory, bytes);
  } catch (_) {
    return null;
  }
}

/// Writes the logo into [directory] unless an identical copy is already
/// there, and returns its `file:` URI.
Future<Uri> writeArtwork(Directory directory, ByteData bytes) async {
  await directory.create(recursive: true);
  final file = File('${directory.path}/nafir_notification_artwork.png');
  final data =
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  if (!await file.exists() || await file.length() != data.length) {
    await file.writeAsBytes(data, flush: true);
  }
  return file.uri;
}
