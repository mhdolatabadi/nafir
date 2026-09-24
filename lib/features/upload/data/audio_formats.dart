/// Mirrors the server's accepted formats so the picker only offers these and
/// the upload form can set the content type the server's policy expects.
const audioContentTypes = {
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
  'opus': 'audio/ogg',
  'wav': 'audio/wav',
  'webm': 'audio/webm',
};

/// Matches the server's default MAX_UPLOAD_BYTES.
const maxUploadBytes = 200 * 1024 * 1024;

String? contentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  return audioContentTypes[fileName.substring(dot + 1).toLowerCase()];
}
