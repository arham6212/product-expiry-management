String formatMinorPrice(int minor, String currencyCode) {
  final major = minor ~/ 100;
  final fraction = (minor % 100).toString().padLeft(2, '0');
  return '$currencyCode $major.$fraction';
}

int? parseMajorPriceToMinor(String value) {
  final normalized = value.trim();
  final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final major = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return major * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

String formatDealDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
