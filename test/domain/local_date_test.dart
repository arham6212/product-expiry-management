import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_validation_exception.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';

void main() {
  group('LocalDate', () {
    test('round-trips ISO format', () {
      final date = LocalDate.parseIso8601('2026-09-03');

      expect(date, LocalDate(2026, 9, 3));
      expect(date.toString(), '2026-09-03');
    });

    test('accepts February 29 in a leap year', () {
      expect(LocalDate(2028, 2, 29).toString(), '2028-02-29');
    });

    test('rejects February 29 outside a leap year', () {
      expect(() => LocalDate(2027, 2, 29), throwsA(isA<DomainValidationException>()));
    });

    test('rejects malformed ISO input', () {
      expect(() => LocalDate.parseIso8601('03/09/2026'), throwsA(isA<DomainValidationException>()));
    });

    test('orders dates without timezones', () {
      expect(LocalDate(2026, 9, 3).compareTo(LocalDate(2026, 9, 12)), isNegative);
    });
  });
}
