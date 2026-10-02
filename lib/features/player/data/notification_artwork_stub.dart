/// Flutter web serves bundled assets under `assets/`, next to the page's base
/// URL; the browser's MediaSession resolves relative artwork against it.
Future<Uri?> resolveArtwork() async =>
    Uri(path: 'assets/assets/icon/nafir.png');
