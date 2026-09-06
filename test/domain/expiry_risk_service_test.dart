import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';

void main() {
  const service = CalendarExpiryRiskService();

  group('CalendarExpiryRiskService', () {
    final boundaryCases = <({int offset, ExpiryRiskCategory expected})>[
      (offset: -1, expected: ExpiryRiskCategory.expired),
      (offset: 0, expected: ExpiryRiskCategory.expiresToday),
      (offset: 1, expected: ExpiryRiskCategory.next7Days),
      (offset: 7, expected: ExpiryRiskCategory.next7Days),
      (offset: 8, expected: ExpiryRiskCategory.days8To30),
      (offset: 30, expected: ExpiryRiskCategory.days8To30),
      (offset: 31, expected: ExpiryRiskCategory.later),
    ];

    for (final boundaryCase in boundaryCases) {
      test('classifies ${boundaryCase.offset} calendar days from the reference date', () {
        final referenceDate = LocalDate(2026, 9, 3);
        final expiry = DateTime.utc(2026, 9, 3).add(Duration(days: boundaryCase.offset));

        expect(
          service.classify(
            expiryDate: LocalDate(expiry.year, expiry.month, expiry.day),
            referenceDate: referenceDate,
          ),
          boundaryCase.expected,
        );
      });
    }

    test('counts calendar dates correctly across a month boundary', () {
      expect(
        service.classify(expiryDate: LocalDate(2026, 10, 1), referenceDate: LocalDate(2026, 9, 30)),
        ExpiryRiskCategory.next7Days,
      );
    });

    test('counts calendar dates correctly across a year boundary', () {
      expect(
        service.classify(expiryDate: LocalDate(2027, 1, 7), referenceDate: LocalDate(2026, 12, 31)),
        ExpiryRiskCategory.next7Days,
      );
      expect(
        service.classify(expiryDate: LocalDate(2027, 1, 8), referenceDate: LocalDate(2026, 12, 31)),
        ExpiryRiskCategory.days8To30,
      );
    });

    test('counts February 29 as a calendar day in leap years', () {
      expect(
        service.classify(expiryDate: LocalDate(2028, 3, 1), referenceDate: LocalDate(2028, 2, 28)),
        ExpiryRiskCategory.next7Days,
      );
    });

    test('returns the same result for repeated identical inputs', () {
      final expiryDate = LocalDate(2026, 10, 3);
      final referenceDate = LocalDate(2026, 9, 3);

      final first = service.classify(expiryDate: expiryDate, referenceDate: referenceDate);
      final second = service.classify(expiryDate: expiryDate, referenceDate: referenceDate);

      expect(first, ExpiryRiskCategory.days8To30);
      expect(second, first);
    });
  });
}
