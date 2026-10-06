import 'persian_digits.dart';

/// A file size for people, in Persian, using the most useful unit.
String formatSize(int bytes) {
  final gigabytes = bytes / (1024 * 1024 * 1024);
  if (gigabytes >= 1)
    return '${persianDigits(gigabytes.toStringAsFixed(1))} گیگابایت';

  final megabytes = bytes / (1024 * 1024);
  return megabytes >= 1
      ? '${persianDigits(megabytes.toStringAsFixed(1))} مگابایت'
      : '${persianDigits((bytes / 1024).ceil())} کیلوبایت';
}
