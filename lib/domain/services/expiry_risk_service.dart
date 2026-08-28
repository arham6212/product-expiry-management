import '../value_objects/local_date.dart';

enum ExpiryRiskCategory { expired, today, within3Days, within7Days, within30Days, safe }

/// Deterministic boundary for expiry classification.
///
/// Its implementation and exact threshold semantics belong to the Phase 2
/// Expiry Engine slice. UI code should depend on this contract rather than
/// calculating date windows itself.
abstract interface class ExpiryRiskService {
  ExpiryRiskCategory classify({required LocalDate expiryDate, required LocalDate today});
}
