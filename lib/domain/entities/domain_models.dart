import '../value_objects/local_date.dart';
import 'domain_validation_exception.dart';

enum BarcodeFormat { ean8, ean13, upcA, upcE, qr, dataMatrix, gs1, unknown }

enum InventoryMovementType { received, sold, disposed, returned, adjusted }

enum ExpiryObservationSource { structuredBarcode, ocr, manual }

enum ExpiryDateType { expiry, useBy, bestBefore, manufactured, unknown }

enum ExpiryActionType { sold, discounted, returnedToSupplier, disposed, kept }

final class User {
  User({
    required this.id,
    required this.displayName,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _requireText(id, 'id');
    _requireText(displayName, 'displayName');
    _requireText(email, 'email');
  }

  final String id;
  final String displayName;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class Shop {
  Shop({
    required this.id,
    required this.name,
    required this.timeZone,
    required this.currencyCode,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
  }) {
    _requireText(id, 'id');
    _requireText(name, 'name');
    _requireText(timeZone, 'timeZone');
    _requireCurrency(currencyCode);
  }

  final String id;
  final String name;
  final String timeZone;
  final String currencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
}

/// Reusable catalog identity. Expiry intentionally does not exist on Product.
final class Product {
  Product({
    required this.id,
    required this.shopId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.brand,
    this.category,
    this.isArchived = false,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(name, 'name');
  }

  final String id;
  final String shopId;
  final String name;
  final String? brand;
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
}

final class ProductBarcode {
  ProductBarcode({
    required this.id,
    required this.shopId,
    required this.productId,
    required this.value,
    required this.format,
    required this.createdAt,
    this.isPrimary = false,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(productId, 'productId');
    _requireText(value, 'value');
  }

  final String id;
  final String shopId;
  final String productId;
  final String value;
  final BarcodeFormat format;
  final bool isPrimary;
  final DateTime createdAt;
}

final class Batch {
  Batch({
    required this.id,
    required this.shopId,
    required this.productId,
    required this.expiryDate,
    required this.currentQuantity,
    required this.createdAt,
    required this.updatedAt,
    this.supplierId,
    this.lotCode,
    this.unitCostMinor,
    this.currencyCode,
    this.isArchived = false,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(productId, 'productId');
    _requireNonNegative(currentQuantity, 'currentQuantity');
    if (unitCostMinor != null) _requireNonNegative(unitCostMinor!, 'unitCostMinor');
    if ((unitCostMinor == null) != (currencyCode == null)) {
      throw const DomainValidationException(
        'unitCostMinor and currencyCode must be provided together.',
      );
    }
    if (currencyCode != null) _requireCurrency(currencyCode!);
  }

  final String id;
  final String shopId;
  final String productId;
  final LocalDate expiryDate;
  final int currentQuantity;
  final String? supplierId;
  final String? lotCode;
  final int? unitCostMinor;
  final String? currencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
}

final class InventoryMovement {
  InventoryMovement({
    required this.id,
    required this.shopId,
    required this.batchId,
    required this.type,
    required this.quantityDelta,
    required this.occurredAt,
    required this.createdAt,
    required this.idempotencyKey,
    this.referenceId,
    this.note,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(batchId, 'batchId');
    _requireText(idempotencyKey, 'idempotencyKey');
    if (quantityDelta == 0) {
      throw const DomainValidationException('quantityDelta must not be zero.');
    }
    final shouldIncrease = type == InventoryMovementType.received;
    final shouldDecrease =
        type == InventoryMovementType.sold ||
        type == InventoryMovementType.disposed ||
        type == InventoryMovementType.returned;
    if (shouldIncrease && quantityDelta < 0) {
      throw const DomainValidationException('Received quantityDelta must be positive.');
    }
    if (shouldDecrease && quantityDelta > 0) {
      throw DomainValidationException('${type.name} quantityDelta must be negative.');
    }
  }

  final String id;
  final String shopId;
  final String batchId;
  final InventoryMovementType type;
  final int quantityDelta;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String idempotencyKey;
  final String? referenceId;
  final String? note;
}

final class ExpiryObservation {
  ExpiryObservation({
    required this.id,
    required this.source,
    required this.dateType,
    required this.confidence,
    required this.rawText,
    required this.isConfirmed,
    required this.observedAt,
    this.batchId,
    this.candidateDate,
  }) {
    _requireText(id, 'id');
    if (confidence < 0 || confidence > 1) {
      throw const DomainValidationException('confidence must be between 0 and 1.');
    }
  }

  final String id;
  final String? batchId;
  final ExpiryObservationSource source;
  final LocalDate? candidateDate;
  final ExpiryDateType dateType;
  final double confidence;
  final String rawText;
  final bool isConfirmed;
  final DateTime observedAt;
}

final class ExpiryAction {
  ExpiryAction({
    required this.id,
    required this.shopId,
    required this.batchId,
    required this.type,
    required this.quantity,
    required this.occurredAt,
    this.movementId,
    this.note,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(batchId, 'batchId');
    if (quantity <= 0) {
      throw const DomainValidationException('quantity must be greater than zero.');
    }
  }

  final String id;
  final String shopId;
  final String batchId;
  final ExpiryActionType type;
  final int quantity;
  final DateTime occurredAt;
  final String? movementId;
  final String? note;
}

final class Supplier {
  Supplier({
    required this.id,
    required this.shopId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.phone,
    this.isActive = true,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(name, 'name');
  }

  final String id;
  final String shopId;
  final String name;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
}

void _requireText(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw DomainValidationException('$fieldName must not be empty.');
  }
}

void _requireNonNegative(int value, String fieldName) {
  if (value < 0) {
    throw DomainValidationException('$fieldName must not be negative.');
  }
}

void _requireCurrency(String value) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
    throw const DomainValidationException(
      'currencyCode must be a three-letter uppercase ISO 4217 code.',
    );
  }
}
