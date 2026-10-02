import 'notification_artwork_stub.dart'
    if (dart.library.io) 'notification_artwork_io.dart' as platform;

/// The bundled Nafir logo shown when a track has no cover art.
const notificationArtworkAsset = 'assets/icon/nafir.png';

/// An artwork URI the system media controls can actually load.
///
/// `audio_service` reads `file:` URIs directly and fetches anything else over
/// HTTP, so an `asset:` URI never shows. On Android the logo is copied to the
/// app's support directory once; on the web the browser loads the bundled
/// asset relative to the page's base URL. Returns null if neither works, in
/// which case the notification simply has no image.
Future<Uri?> resolveNotificationArtwork() => platform.resolveArtwork();
