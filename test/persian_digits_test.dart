import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/persian_digits.dart';
import 'package:nafir/core/format_size.dart';

void main() {
  test('converts both numeral sets and preserves surrounding text', () {
    expect(persianDigits('0123456789 / ٠١٢٣٤٥٦٧٨٩'), '۰۱۲۳۴۵۶۷۸۹ / ۰۱۲۳۴۵۶۷۸۹');
    expect(persianDigits('۰۱:۲۳ · ۴۵٪'), '۰۱:۲۳ · ۴۵٪');
    expect(persianDigits(-12.5), '-۱۲.۵');
  });
  test('formats storage boundaries in Persian', () {
    expect(formatSize(0), '۰ کیلوبایت');
    expect(formatSize(1024 * 1024), '۱.۰ مگابایت');
    expect(formatSize(1024 * 1024 * 1024), '۱.۰ گیگابایت');
  });
}
