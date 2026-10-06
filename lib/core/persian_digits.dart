/// Formats display text without changing stored values or protocol data.
String persianDigits(Object value) {
  const latin = '0123456789';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return value.toString().split('').map((character) {
    final index = latin.indexOf(character);
    if (index >= 0) return persian[index];
    final arabicIndex = arabic.indexOf(character);
    return arabicIndex >= 0 ? persian[arabicIndex] : character;
  }).join();
}
