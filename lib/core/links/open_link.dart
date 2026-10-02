import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app: the browser on Android, a new tab on the
/// web. Returns false when nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> openExternalLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
