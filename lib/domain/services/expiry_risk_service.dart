import '../value_objects/local_date.dart';

enum ExpiryRiskCategory { expired, expiresToday, next7Days, days8To30, later }

/// Deterministic boundary for expiry classification.
abstract interface class ExpiryRiskService {
  ExpiryRiskCategory classify({required LocalDate expiryDate, required LocalDate referenceDate});
}

/// Classifies expiry using whole calendar dates with inclusive day boundaries.
///
/// [LocalDate] has no time-of-day or timezone. Converting both values to UTC
/// midnight is therefore only a safe way to count calendar days; it does not
/// reinterpret either value as an expiry instant.
final class CalendarExpiryRiskService implements ExpiryRiskService {
  const CalendarExpiryRiskService();

  @override
  ExpiryRiskCategory classify({required LocalDate expiryDate, required LocalDate referenceDate}) {
    final daysUntilExpiry = referenceDate.daysUntil(expiryDate);

    if (daysUntilExpiry < 0) return ExpiryRiskCategory.expired;
    if (daysUntilExpiry == 0) return ExpiryRiskCategory.expiresToday;
    if (daysUntilExpiry <= 7) return ExpiryRiskCategory.next7Days;
    if (daysUntilExpiry <= 30) return ExpiryRiskCategory.days8To30;
    return ExpiryRiskCategory.later;
  }
}
