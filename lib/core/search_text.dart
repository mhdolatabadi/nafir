/// Text as search compares it: lower case, with Persian and Arabic letter
/// forms unified (ي/ى → ی, ك → ک, hamza seats and ة folded), Arabic
/// diacritics, tatweel, ZWNJ and other joiners dropped, accented Latin
/// letters reduced to their base letter, every digit made Latin and runs of
/// space collapsed. So «كتاب‌ها» finds «کتابها» and "Beyoncé" finds "beyonce".
String normalizeForSearch(String text) {
  final out = StringBuffer();
  var space = false;
  for (final rune in text.toLowerCase().runes) {
    if (_ignored(rune)) continue;
    final mapped = _folded[rune] ?? _digit(rune) ?? rune;
    final isSpace = mapped == 0x20 || mapped == 0x09 || mapped == 0x0a;
    if (isSpace) {
      space = out.isNotEmpty;
      continue;
    }
    if (space) out.write(' ');
    space = false;
    out.writeCharCode(mapped);
  }
  return out.toString();
}

/// Whether every word of [query] appears in one of [fields], in any order,
/// as [normalizeForSearch] compares them. An empty query matches anything.
bool matchesSearch(String query, Iterable<String?> fields) {
  final words = normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = normalizeForSearch(fields.whereType<String>().join(' '));
  return words.every(haystack.contains);
}

bool _ignored(int rune) =>
    // ZWNJ, ZWJ, LRM/RLM, soft hyphen and tatweel.
    rune == 0x200c ||
    rune == 0x200d ||
    rune == 0x200e ||
    rune == 0x200f ||
    rune == 0x00ad ||
    rune == 0x0640 ||
    // Arabic harakat, superscript alef and Quranic marks.
    (rune >= 0x064b && rune <= 0x065f) ||
    rune == 0x0670 ||
    (rune >= 0x06d6 && rune <= 0x06ed) ||
    // Combining accents left by decomposed Latin text.
    (rune >= 0x0300 && rune <= 0x036f);

int? _digit(int rune) {
  if (rune >= 0x06f0 && rune <= 0x06f9) return 0x30 + rune - 0x06f0;
  if (rune >= 0x0660 && rune <= 0x0669) return 0x30 + rune - 0x0660;
  return null;
}

const _folded = <int, int>{
  0x064a: 0x06cc, // ي → ی
  0x0649: 0x06cc, // ى → ی
  0x0626: 0x06cc, // ئ → ی
  0x0643: 0x06a9, // ك → ک
  0x0622: 0x0627, // آ → ا
  0x0623: 0x0627, // أ → ا
  0x0625: 0x0627, // إ → ا
  0x0671: 0x0627, // ٱ → ا
  0x0624: 0x0648, // ؤ → و
  0x0629: 0x0647, // ة → ه
  0x06c0: 0x0647, // ۀ → ه
  0x00a0: 0x20, // no-break space
  0x00e0: 0x61, 0x00e1: 0x61, 0x00e2: 0x61, 0x00e3: 0x61, 0x00e4: 0x61,
  0x00e5: 0x61, 0x00e7: 0x63, 0x00e8: 0x65, 0x00e9: 0x65, 0x00ea: 0x65,
  0x00eb: 0x65, 0x00ec: 0x69, 0x00ed: 0x69, 0x00ee: 0x69, 0x00ef: 0x69,
  0x00f1: 0x6e, 0x00f2: 0x6f, 0x00f3: 0x6f, 0x00f4: 0x6f, 0x00f5: 0x6f,
  0x00f6: 0x6f, 0x00f8: 0x6f, 0x00f9: 0x75, 0x00fa: 0x75, 0x00fb: 0x75,
  0x00fc: 0x75, 0x00fd: 0x79, 0x00ff: 0x79,
};
