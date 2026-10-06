import 'package:flutter/material.dart';
import 'package:nafir/core/links/open_link.dart';

/// Where a public page of the site, such as `/privacy`, lives; null when
/// there is no server.
typedef SitePageResolver = Uri? Function(String path);

/// Opens the site page at [path] outside the app, and says so when it could
/// not be opened.
Future<void> openSitePage(
  BuildContext context,
  String path, {
  required SitePageResolver siteUri,
  required LinkOpener openLink,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = siteUri(path);
  final opened = uri != null && await openLink(uri);
  if (opened) return;
  messenger?.showSnackBar(const SnackBar(
    content: Text('باز کردن صفحه ممکن نشد.'),
  ));
}
