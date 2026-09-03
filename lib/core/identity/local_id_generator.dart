abstract final class LocalIdGenerator {
  static var _sequence = 0;

  static String next(String prefix) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final sequence = _sequence++;
    return '$prefix-$timestamp-$sequence';
  }
}
