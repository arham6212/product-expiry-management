import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/local_date.dart';
import 'expiry_dashboard.dart';

typedef IdempotencyKeyGenerator = String Function();

final class ReceiveStockInput {
  const ReceiveStockInput({
    required this.shopId,
    required this.productId,
    this.quantity,
    this.sellingPriceMinor,
    this.expiryDate,
    this.lotNumber,
  });

  final String shopId;
  final String productId;
  final int? quantity;
  final int? sellingPriceMinor;
  final LocalDate? expiryDate;
  final String? lotNumber;
}

final class ReceivingRequest {
  const ReceivingRequest({
    required this.shopId,
    required this.productId,
    this.quantity,
    required this.sellingPriceMinor,
    required this.expiryDate,
    required this.idempotencyKey,
    this.lotNumber,
  });

  final String shopId;
  final String productId;
  final int? quantity;
  final int sellingPriceMinor;
  final LocalDate expiryDate;
  final String? lotNumber;
  final String idempotencyKey;

  bool hasSamePayload(ReceivingRequest other) {
    return shopId == other.shopId &&
        productId == other.productId &&
        quantity == other.quantity &&
        expiryDate == other.expiryDate &&
        lotNumber == other.lotNumber;
  }
}

final class ReceivingReceipt {
  const ReceivingReceipt({required this.batch, required this.movement, required this.wasDuplicate});

  final Batch batch;
  final InventoryMovement movement;
  final bool wasDuplicate;
}

enum InventoryRepositoryFailureKind {
  authorization,
  productUnavailable,
  idempotencyConflict,
  invalidInput,
  unavailable,
  invalidResponse,
}

final class InventoryRepositoryException implements Exception {
  const InventoryRepositoryException(this.kind, this.message, {this.cause});

  final InventoryRepositoryFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'InventoryRepositoryException($kind): $message';
}

abstract interface class InventoryRepository {
  Future<List<Product>> listProducts({required String shopId});

  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId});

  /// Persists one Batch and its initial RECEIVED movement atomically.
  Future<ReceivingReceipt> receive(ReceivingRequest request);
}

sealed class ReceiveStockResult {
  const ReceiveStockResult({required this.idempotencyKey});

  /// Present after a valid logical submission has been prepared. Pass this
  /// same key to [ReceiveStock.call] when retrying an uncertain outcome.
  final String? idempotencyKey;
}

final class ReceiveStockSuccess extends ReceiveStockResult {
  const ReceiveStockSuccess({required this.receipt, required String idempotencyKey})
    : super(idempotencyKey: idempotencyKey);

  final ReceivingReceipt receipt;
}

final class ReceiveStockInvalidInput extends ReceiveStockResult {
  const ReceiveStockInvalidInput({required this.field, required this.message})
    : super(idempotencyKey: null);

  final String field;
  final String message;
}

final class ReceiveStockAuthorizationFailure extends ReceiveStockResult {
  const ReceiveStockAuthorizationFailure({required String idempotencyKey})
    : super(idempotencyKey: idempotencyKey);
}

final class ReceiveStockProductUnavailable extends ReceiveStockResult {
  const ReceiveStockProductUnavailable({required String idempotencyKey})
    : super(idempotencyKey: idempotencyKey);
}

final class ReceiveStockIdempotencyConflict extends ReceiveStockResult {
  const ReceiveStockIdempotencyConflict({required String idempotencyKey})
    : super(idempotencyKey: idempotencyKey);
}

final class ReceiveStockBackendUnavailable extends ReceiveStockResult {
  const ReceiveStockBackendUnavailable({required String idempotencyKey})
    : super(idempotencyKey: idempotencyKey);
}

final class ReceiveStock {
  ReceiveStock({
    required InventoryRepository repository,
    required IdempotencyKeyGenerator idempotencyKeyGenerator,
  }) : _repository = repository,
       _idempotencyKeyGenerator = idempotencyKeyGenerator;

  static const maxQuantity = 2147483647;
  static const maxSellingPriceMinor = 2147483647;
  static const maxLotNumberLength = 120;

  final InventoryRepository _repository;
  final IdempotencyKeyGenerator _idempotencyKeyGenerator;

  Future<ReceiveStockResult> call(ReceiveStockInput input, {String? retryIdempotencyKey}) async {
    final invalid = _validate(input);
    if (invalid != null) return invalid;

    final idempotencyKey = retryIdempotencyKey ?? _idempotencyKeyGenerator();
    if (idempotencyKey.trim().isEmpty) {
      return const ReceiveStockInvalidInput(
        field: 'idempotencyKey',
        message: 'The receiving request requires an idempotency key.',
      );
    }

    final request = ReceivingRequest(
      shopId: input.shopId.trim(),
      productId: input.productId.trim(),
      quantity: input.quantity,
      sellingPriceMinor: input.sellingPriceMinor!,
      expiryDate: input.expiryDate!,
      lotNumber: _normalizeLotNumber(input.lotNumber),
      idempotencyKey: idempotencyKey.trim(),
    );

    try {
      final receipt = await _repository.receive(request);
      return ReceiveStockSuccess(receipt: receipt, idempotencyKey: request.idempotencyKey);
    } on InventoryRepositoryException catch (error) {
      return switch (error.kind) {
        InventoryRepositoryFailureKind.authorization => ReceiveStockAuthorizationFailure(
          idempotencyKey: request.idempotencyKey,
        ),
        InventoryRepositoryFailureKind.productUnavailable => ReceiveStockProductUnavailable(
          idempotencyKey: request.idempotencyKey,
        ),
        InventoryRepositoryFailureKind.idempotencyConflict => ReceiveStockIdempotencyConflict(
          idempotencyKey: request.idempotencyKey,
        ),
        InventoryRepositoryFailureKind.invalidInput => ReceiveStockInvalidInput(
          field: 'request',
          message: error.message,
        ),
        InventoryRepositoryFailureKind.unavailable ||
        InventoryRepositoryFailureKind.invalidResponse => ReceiveStockBackendUnavailable(
          idempotencyKey: request.idempotencyKey,
        ),
      };
    } on Object {
      return ReceiveStockBackendUnavailable(idempotencyKey: request.idempotencyKey);
    }
  }

  ReceiveStockInvalidInput? _validate(ReceiveStockInput input) {
    if (input.shopId.trim().isEmpty) {
      return const ReceiveStockInvalidInput(
        field: 'shopId',
        message: 'Select a shop before receiving stock.',
      );
    }
    if (input.productId.trim().isEmpty) {
      return const ReceiveStockInvalidInput(
        field: 'productId',
        message: 'Select an existing product.',
      );
    }
    if (input.quantity != null && input.quantity! <= 0) {
      return const ReceiveStockInvalidInput(
        field: 'quantity',
        message: 'Quantity must be greater than zero.',
      );
    }
    if (input.quantity != null && input.quantity! > maxQuantity) {
      return const ReceiveStockInvalidInput(
        field: 'quantity',
        message: 'Quantity exceeds the supported maximum of 2,147,483,647.',
      );
    }
    if (input.sellingPriceMinor == null) {
      return const ReceiveStockInvalidInput(
        field: 'sellingPrice',
        message: 'Enter a selling price.',
      );
    }
    if (input.sellingPriceMinor! <= 0) {
      return const ReceiveStockInvalidInput(
        field: 'sellingPrice',
        message: 'Selling price must be greater than zero.',
      );
    }
    if (input.sellingPriceMinor! > maxSellingPriceMinor) {
      return const ReceiveStockInvalidInput(
        field: 'sellingPrice',
        message: 'Selling price exceeds the supported maximum.',
      );
    }
    if (input.expiryDate == null) {
      return const ReceiveStockInvalidInput(field: 'expiryDate', message: 'Enter an expiry date.');
    }
    final lotNumber = _normalizeLotNumber(input.lotNumber);
    if (lotNumber != null && lotNumber.length > maxLotNumberLength) {
      return const ReceiveStockInvalidInput(
        field: 'lotNumber',
        message: 'Batch or lot number must be 120 characters or less.',
      );
    }
    return null;
  }
}

int? parseSellingPriceMinor(String value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final major = int.tryParse(match.group(1)!);
  if (major == null) return null;
  final fractionText = match.group(2) ?? '';
  final fraction = fractionText.isEmpty ? 0 : int.parse(fractionText.padRight(2, '0'));
  if (major > ReceiveStock.maxSellingPriceMinor ~/ 100) return null;
  final minor = major * 100 + fraction;
  if (minor <= 0 || minor > ReceiveStock.maxSellingPriceMinor) return null;
  return minor;
}

String formatSellingPriceMinor(int minor) {
  final major = minor ~/ 100;
  final fraction = (minor % 100).toString().padLeft(2, '0');
  return '$major.$fraction';
}

String? _normalizeLotNumber(String? value) {
  if (value == null) return null;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}
