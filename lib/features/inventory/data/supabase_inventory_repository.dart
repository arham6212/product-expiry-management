import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/value_objects/local_date.dart';
import '../application/receive_stock.dart';

final class SupabaseInventoryRepository implements InventoryRepository {
  const SupabaseInventoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    try {
      final rows = await _client
          .from('products')
          .select(
            'id,shop_id,name,brand,image_url,source,source_reference,catalog_product_id,'
            'created_at,updated_at',
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
  Future<ReceivingReceipt> receive(ReceivingRequest request) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'receive_product_stock',
        params: {
          'target_shop_id': request.shopId,
          'target_product_id': request.productId,
          'received_quantity': request.quantity,
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

ReceivingReceipt _mapReceipt(Map<String, dynamic> row) {
  final batch = Batch(
    id: _requiredString(row, 'batch_id'),
    shopId: _requiredString(row, 'batch_shop_id'),
    productId: _requiredString(row, 'batch_product_id'),
    expiryDate: _optionalLocalDate(row, 'batch_expiry_date'),
    lotCode: _optionalString(row, 'batch_lot_number'),
    currentQuantity: _requiredInt(row, 'batch_current_quantity'),
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
    quantityDelta: _requiredInt(row, 'movement_quantity_delta'),
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

Product _mapProduct(Map<String, dynamic> row) {
  final imageValue = _optionalString(row, 'image_url');
  return Product(
    id: _requiredString(row, 'id'),
    shopId: _requiredString(row, 'shop_id'),
    name: _requiredString(row, 'name'),
    brand: _optionalString(row, 'brand'),
    imageUrl: imageValue == null ? null : Uri.parse(imageValue),
    source: switch (_requiredString(row, 'source')) {
      'local_manual' => ProductSource.localManual,
      'open_food_facts' => ProductSource.openFoodFacts,
      _ => throw const FormatException('Unknown product source.'),
    },
    sourceReference: _optionalString(row, 'source_reference'),
    catalogProductId: _optionalString(row, 'catalog_product_id'),
    createdAt: _requiredDateTime(row, 'created_at'),
    updatedAt: _requiredDateTime(row, 'updated_at'),
  );
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

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! int) throw FormatException('Invalid $key.');
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  return DateTime.parse(_requiredString(row, key)).toUtc();
}

LocalDate? _optionalLocalDate(Map<String, dynamic> row, String key) {
  final value = _optionalString(row, key);
  return value == null ? null : LocalDate.parseIso8601(value);
}
