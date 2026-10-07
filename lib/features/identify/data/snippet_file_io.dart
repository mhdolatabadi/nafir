import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the recorder writes a snippet on Android: a private temporary file.
Future<String> snippetPath() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/rhythmo_snippet_${DateTime.now().microsecondsSinceEpoch}.wav';
}

/// Reads the recorded snippet and deletes it right away.
Future<Uint8List> takeSnippet(String path) async {
  final file = File(path);
  try {
    return await file.readAsBytes();
  } finally {
    await discardSnippet(path);
  }
}

/// Deletes a snippet that won't be sent, for example after a cancel.
Future<void> discardSnippet(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}
