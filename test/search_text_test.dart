import 'package:flutter_test/flutter_test.dart';
import 'package:nafir/core/search_text.dart';

void main() {
  test('Arabic letter forms match their Persian ones', () {
    expect(normalizeForSearch('علي'), normalizeForSearch('علی'));
    expect(normalizeForSearch('كوچه'), normalizeForSearch('کوچه'));
    expect(normalizeForSearch('مدرسة'), normalizeForSearch('مدرسه'));
    expect(normalizeForSearch('أحمد'), normalizeForSearch('احمد'));
  });

  test('ZWNJ, diacritics and tatweel are ignored', () {
    expect(normalizeForSearch('می‌خواهم'), 'میخواهم');
    expect(normalizeForSearch('مُحَمَّد'), 'محمد');
    expect(normalizeForSearch('سـلام'), 'سلام');
  });

  test('case, Latin accents, digits and spacing are folded', () {
    expect(normalizeForSearch('  Beyoncé   LIVE '), 'beyonce live');
    expect(normalizeForSearch('آهنگ ۱۲'), 'اهنگ 12');
    expect(normalizeForSearch('track ٣'), 'track 3');
  });

  test('joined and spaced Persian spellings match in either direction', () {
    expect(matchesSearch('میخواهم', ['می خواهم']), isTrue);
    expect(matchesSearch('می خواهم', ['می‌خواهم']), isTrue);
    expect(matchesSearch('دلآرام', ['دل آرام']), isTrue);
    expect(matchesSearch('دلآرام', ['دل', 'آرام']), isFalse);
  });

  test('copied Unicode whitespace separates query words', () {
    expect(normalizeForSearch('one\u202ftwo\r\nthree\u3000four'),
        'one two three four');
    expect(matchesSearch('آهنگ\u2009۱۲', ['آهنگ 12']), isTrue);
  });

  test('every query word must appear in some field', () {
    final fields = ['كتاب‌ها', 'Shajarian', null, 'song.MP3'];
    expect(matchesSearch('کتابها', fields), isTrue);
    expect(matchesSearch('shaj کتاب', fields), isTrue);
    expect(matchesSearch('mp3', fields), isTrue);
    expect(matchesSearch('shajarian ناظری', fields), isFalse);
    expect(matchesSearch('   ', fields), isTrue);
  });
}
