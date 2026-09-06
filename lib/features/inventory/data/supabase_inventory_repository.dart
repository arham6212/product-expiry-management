import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/domain_validation_exception.dart';
import '../../../domain/services/expiry_risk_service.dart';
import '../../../domain/value_objects/local_date.dart';
import '../application/expiry_dashboard.dart';
import '../application/receive_stock.dart';

final class SupabaseInventoryRepository implements InventoryRepository {
  const SupabaseInventoryRepository(
    this._client, {
    ExpiryRiskService expiryRiskService = const CalendarExpiryRiskService(),
  }) : _expiryRiskService = expiryRiskService;

  final SupabaseClient _client;
  final ExpiryRiskService _expiryRiskService;

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    try {
      final rows = await _client
          .from('products')
          .select(
            'id,shop_id,name,brand,image_url,source,source_reference,catalog_product_id,'
            'selling_price_minor,created_at,updated_at,product_barcodes(barcode,is_primary)',
          )
          .eq('shop_id', shopId)
          .order('name');
      return List.unmodifiable(rows.map(_mapProduct));
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error, operation: 'Products could not be loaded.');
    } on FormatException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidResponse,
        'Product listing returned invalid data.',
        cause: error,
      );
    } on InventoryRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Products could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) async {
    final normalizedShopId = shopId.trim();
    if (!_isUuid(normalizedShopId)) {
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidInput,
        'A valid Shop ID is required to load the expiry dashboard.',
      );
    }

    try {
      final rows = await _client.rpc<List<dynamic>>(
        'get_expiry_dashboard',
        params: {'target_shop_id': normalizedShopId},
      );
      return _mapExpiryDashboardSnapshot(
        rows,
        requestedShopId: normalizedShopId,
        expiryRiskService: _expiryRiskService,
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error, operation: 'Expiry dashboard could not be loaded.');
    } on FormatException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidResponse,
        'Expiry dashboard returned invalid data.',
        cause: error,
      );
    } on DomainValidationException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidResponse,
        'Expiry dashboard returned invalid data.',
        cause: error,
      );
    } on InventoryRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Expiry dashboard could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'receive_product_stock',
        params: {
          'target_shop_id': request.shopId,
          'target_product_id': request.productId,
          'received_quantity': request.quantity,
          'target_selling_price_minor': request.sellingPriceMinor,
          'target_expiry_date': request.expiryDate.toString(),
          'target_lot_number': request.lotNumber,
          'request_idempotency_key': request.idempotencyKey,
        },
      );
      if (rows.length != 1 || rows.single is! Map<String, dynamic>) {
        throw const FormatException('Expected one receiving receipt.');
      }
      final receipt = _mapReceipt(rows.single! as Map<String, dynamic>);
      if (receipt.batch.shopId != request.shopId ||
          receipt.batch.productId != request.productId ||
          receipt.batch.expiryDate != request.expiryDate ||
          receipt.batch.lotCode != request.lotNumber ||
          receipt.batch.currentQuantity != request.quantity ||
          receipt.movement.idempotencyKey != request.idempotencyKey) {
        throw const FormatException('Receiving receipt does not match the request.');
      }
      return receipt;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error, operation: 'Received stock could not be saved.');
    } on FormatException catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidResponse,
        'Receiving returned invalid data.',
        cause: error,
      );
    } on InventoryRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Received stock could not be saved.',
        cause: error,
      );
    }
  }
}

ExpiryDashboardSnapshot _mapExpiryDashboardSnapshot(
  List<dynamic> rows, {
  required String requestedShopId,
  required ExpiryRiskService expiryRiskService,
}) {
  if (rows.isEmpty) {
    throw const FormatException('Expected dashboard metadata.');
  }

  final mappedRows = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Expected dashboard row objects.');
    }
    if (!_expiryDashboardKeys.every(row.containsKey)) {
      throw const FormatException('Dashboard row is missing required fields.');
    }
    mappedRows.add(row);
  }

  final referenceDate = _requiredLocalDate(mappedRows.first, 'reference_date');
  final items = <ExpiryDashboardItem>[];

  for (final row in mappedRows) {
    final rowReferenceDate = _requiredLocalDate(row, 'reference_date');
    if (rowReferenceDate != referenceDate) {
      throw const FormatException('Dashboard rows disagree on the reference date.');
    }

    final rowShopId = _requiredUuidString(row, 'shop_id');
    if (rowShopId != requestedShopId) {
      throw const FormatException('Dashboard row belongs to another Shop.');
    }

    if (row['batch_id'] == null) {
      if (mappedRows.length != 1 || !_isEmptyDashboardMetadataRow(row)) {
        throw const FormatException('Invalid empty dashboard metadata.');
      }
      continue;
    }

    final expiryDate = _optionalLocalDate(row, 'expiry_date');
    final daysToExpiry = _optionalInt(row, 'days_to_expiry');
    final riskCategory = expiryDate == null
        ? null
        : expiryRiskService.classify(expiryDate: expiryDate, referenceDate: referenceDate);

    if (expiryDate == null) {
      if (daysToExpiry != null) {
        throw const FormatException('Unknown expiry must not have a day offset.');
      }
    } else if (daysToExpiry == null || referenceDate.daysUntil(expiryDate) != daysToExpiry) {
      throw const FormatException('Expiry day offset is inconsistent.');
    }

    final currentQuantity = _nullableQuantity(row, 'current_quantity');
    if (currentQuantity != null && currentQuantity <= 0) {
      throw const FormatException('Dashboard quantity must be positive.');
    }

    items.add(
      ExpiryDashboardItem(
        shopId: rowShopId,
        batchId: _requiredUuidString(row, 'batch_id'),
        productId: _requiredUuidString(row, 'product_id'),
        productName: _requiredNonBlankString(row, 'product_name'),
        productBrand: _optionalNonBlankString(row, 'product_brand'),
        expiryDate: expiryDate,
        daysToExpiry: daysToExpiry,
        riskCategory: riskCategory,
        currentQuantity: currentQuantity,
        lotNumber: _optionalNonBlankString(row, 'lot_number'),
        receivedAt: _requiredDateTime(row, 'received_at'),
      ),
    );
  }

  return ExpiryDashboardSnapshot(referenceDate: referenceDate, items: items);
}

bool _isEmptyDashboardMetadataRow(Map<String, dynamic> row) {
  return const [
    'batch_id',
    'product_id',
    'product_name',
    'product_brand',
    'expiry_date',
    'days_to_expiry',
    'current_quantity',
    'lot_number',
    'received_at',
  ].every((key) => row[key] == null);
}

const _expiryDashboardKeys = [
  'reference_date',
  'shop_id',
  'batch_id',
  'product_id',
  'product_name',
  'product_brand',
  'expiry_date',
  'days_to_expiry',
  'current_quantity',
  'lot_number',
  'received_at',
];

ReceivingReceipt _mapReceipt(Map<String, dynamic> row) {
  final batch = Batch(
    id: _requiredString(row, 'batch_id'),
    shopId: _requiredString(row, 'batch_shop_id'),
    productId: _requiredString(row, 'batch_product_id'),
    expiryDate: _optionalLocalDate(row, 'batch_expiry_date'),
    lotCode: _optionalString(row, 'batch_lot_number'),
    currentQuantity: _nullableQuantity(row, 'batch_current_quantity'),
    createdAt: _requiredDateTime(row, 'batch_created_at'),
    updatedAt: _requiredDateTime(row, 'batch_updated_at'),
  );
  final movement = InventoryMovement(
    id: _requiredString(row, 'movement_id'),
    shopId: _requiredString(row, 'movement_shop_id'),
    batchId: _requiredString(row, 'movement_batch_id'),
    type: switch (_requiredString(row, 'movement_type')) {
      'received' => InventoryMovementType.received,
      _ => throw const FormatException('Expected a RECEIVED movement.'),
    },
    quantityDelta: _nullableQuantity(row, 'movement_quantity_delta'),
    occurredAt: _requiredDateTime(row, 'movement_occurred_at'),
    createdAt: _requiredDateTime(row, 'movement_created_at'),
    idempotencyKey: _requiredString(row, 'movement_idempotency_key'),
  );
  if (batch.shopId != movement.shopId ||
      batch.id != movement.batchId ||
      batch.currentQuantity != movement.quantityDelta) {
    throw const FormatException('Receiving receipt records are inconsistent.');
  }
  final wasDuplicate = row['was_duplicate'];
  if (wasDuplicate is! bool) throw const FormatException('Missing duplicate outcome.');
  return ReceivingReceipt(batch: batch, movement: movement, wasDuplicate: wasDuplicate);
}

String? _productBarcode(Map<String, dynamic> row) {
  final values = row['product_barcodes'];
  if (values == null) return null;
  if (values is! List) throw const FormatException('Invalid product barcodes.');
  final mappings = values.cast<Map<String, dynamic>>();
  final selected =
      mappings.where((m) => m['is_primary'] == true).firstOrNull ?? mappings.firstOrNull;
  return selected == null ? null : _optionalString(selected, 'barcode');
}

Product _mapProduct(Map<String, dynamic> row) {
  final imageValue = _optionalString(row, 'image_url');
  return Product(
    id: _requiredString(row, 'id'),
    shopId: _requiredString(row, 'shop_id'),
    name: _requiredString(row, 'name'),
    brand: _optionalString(row, 'brand'),
    barcode: _productBarcode(row),
    imageUrl: imageValue == null ? null : Uri.parse(imageValue),
    source: switch (_requiredString(row, 'source')) {
      'local_manual' => ProductSource.localManual,
      'open_food_facts' => ProductSource.openFoodFacts,
      _ => throw const FormatException('Unknown product source.'),
    },
    sourceReference: _optionalString(row, 'source_reference'),
    catalogProductId: _optionalString(row, 'catalog_product_id'),
    sellingPriceMinor: _optionalPositiveInt(row, 'selling_price_minor'),
    createdAt: _requiredDateTime(row, 'created_at'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
  );
}

int? _optionalPositiveInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! int || value <= 0) throw FormatException('Invalid $key.');
  return value;
}

InventoryRepositoryException _mapPostgrestException(
  PostgrestException error, {
  required String operation,
}) {
  final kind = switch (error.code) {
    '42501' => InventoryRepositoryFailureKind.authorization,
    'P0002' => InventoryRepositoryFailureKind.productUnavailable,
    '23505' => InventoryRepositoryFailureKind.idempotencyConflict,
    '22023' || '22P02' => InventoryRepositoryFailureKind.invalidInput,
    _ => InventoryRepositoryFailureKind.unavailable,
  };
  return InventoryRepositoryException(kind, operation, cause: error);
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key.');
  return value;
}

String _requiredNonBlankString(Map<String, dynamic> row, String key) {
  final value = _requiredString(row, key);
  if (value.trim().isEmpty) throw FormatException('Invalid $key.');
  return value;
}

String _requiredUuidString(Map<String, dynamic> row, String key) {
  final value = _requiredString(row, key);
  if (!_isUuid(value)) throw FormatException('Invalid $key.');
  return value;
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

String? _optionalNonBlankString(Map<String, dynamic> row, String key) {
  final value = _optionalString(row, key);
  if (value != null && value.trim().isEmpty) throw FormatException('Invalid $key.');
  return value;
}

int? _nullableQuantity(Map<String, dynamic> row, String key) {
  if (!row.containsKey(key)) throw FormatException('Missing $key.');
  return _optionalInt(row, key);
}

int? _optionalInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('Invalid $key.');
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final value = DateTime.parse(_requiredString(row, key));
  if (!value.isUtc) throw FormatException('$key must include a UTC offset.');
  return value.toUtc();
}

LocalDate? _optionalLocalDate(Map<String, dynamic> row, String key) {
  final value = _optionalString(row, key);
  return value == null ? null : LocalDate.parseIso8601(value);
}

LocalDate _requiredLocalDate(Map<String, dynamic> row, String key) {
  return LocalDate.parseIso8601(_requiredString(row, key));
}

bool _isUuid(String value) {
  return _uuidPattern.hasMatch(value);
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
