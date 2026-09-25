/// A file size for people, in Persian: megabytes, or kilobytes when small.
String formatSize(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  return megabytes >= 1
      ? '${megabytes.toStringAsFixed(1)} مگابایت'
      : '${(bytes / 1024).ceil()} کیلوبایت';
}
