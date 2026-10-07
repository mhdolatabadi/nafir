import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// On the web the recorder keeps the snippet in memory and ignores the path.
Future<String> snippetPath() async => '';

/// Reads the in-memory recording at its blob URL, then releases it.
Future<Uint8List> takeSnippet(String url) async {
  try {
    return (await http.get(Uri.parse(url))).bodyBytes;
  } finally {
    await discardSnippet(url);
  }
}

/// Releases a recording that won't be sent.
Future<void> discardSnippet(String? url) async {
  if (url != null && url.startsWith('blob:')) web.URL.revokeObjectURL(url);
}
