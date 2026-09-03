import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/local_date.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock.dart';
import 'package:product_expiry_management/features/inventory/data/supabase_inventory_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const shopId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const productId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const batchId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  const movementId = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
  final receiptJson = <String, Object?>{
    'batch_id': batchId,
    'batch_shop_id': shopId,
    'batch_product_id': productId,
    'batch_expiry_date': '2026-09-12',
    'batch_lot_number': 'LOT-7',
    'batch_current_quantity': 20,
    'batch_created_at': '2026-08-30T10:00:00Z',
    'batch_updated_at': '2026-08-30T10:00:00Z',
    'movement_id': movementId,
    'movement_shop_id': shopId,
    'movement_batch_id': batchId,
    'movement_type': 'received',
    'movement_quantity_delta': 20,
    'movement_occurred_at': '2026-08-30T10:00:00Z',
    'movement_created_at': '2026-08-30T10:00:00Z',
    'movement_idempotency_key': 'receive-1',
    'was_duplicate': false,
  };

  test('maps the atomic RPC receipt and sends selected-shop input', () async {
    late http.Request captured;
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([receiptJson]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final receipt = await repository.receive(
      ReceivingRequest(
        shopId: shopId,
        productId: productId,
        quantity: 20,
        expiryDate: LocalDate(2026, 9, 12),
        lotNumber: 'LOT-7',
        idempotencyKey: 'receive-1',
      ),
    );

    expect(receipt.batch.id, batchId);
    expect(receipt.batch.expiryDate, LocalDate(2026, 9, 12));
    expect(receipt.batch.lotCode, 'LOT-7');
    expect(receipt.movement.type, InventoryMovementType.received);
    expect(receipt.wasDuplicate, isFalse);
    expect(captured.url.path, '/rest/v1/rpc/receive_product_stock');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['target_shop_id'], shopId);
    expect(body['target_product_id'], productId);
    expect(body['received_quantity'], 20);
    expect(body['target_expiry_date'], '2026-09-12');
    expect(body['target_lot_number'], 'LOT-7');
    expect(body['request_idempotency_key'], 'receive-1');
  });

  test('rejects a null expiry in an idempotent receiving response', () async {
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                ...receiptJson,
                'batch_expiry_date': null,
                'batch_lot_number': null,
                'was_duplicate': true,
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.receive(
        ReceivingRequest(
          shopId: shopId,
          productId: productId,
          quantity: 20,
          expiryDate: LocalDate(2026, 9, 12),
          idempotencyKey: 'receive-1',
        ),
      ),
      throwsA(
        isA<InventoryRepositoryException>().having(
          (error) => error.kind,
          'kind',
          InventoryRepositoryFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('lists Products only through the explicitly selected shop query', () async {
    late http.Request captured;
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {
                'id': productId,
                'shop_id': shopId,
                'name': 'Milk',
                'brand': null,
                'image_url': null,
                'source': 'local_manual',
                'source_reference': null,
                'created_at': '2026-08-30T10:00:00Z',
                'updated_at': '2026-08-30T10:00:00Z',
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final products = await repository.listProducts(shopId: shopId);

    expect(products.single.shopId, shopId);
    expect(captured.url.path, '/rest/v1/products');
    expect(captured.url.queryParameters['shop_id'], 'eq.$shopId');
  });

  for (final entry in <String, InventoryRepositoryFailureKind>{
    '42501': InventoryRepositoryFailureKind.authorization,
    'P0002': InventoryRepositoryFailureKind.productUnavailable,
    '23505': InventoryRepositoryFailureKind.idempotencyConflict,
    '22023': InventoryRepositoryFailureKind.invalidInput,
    'XX000': InventoryRepositoryFailureKind.unavailable,
  }.entries) {
    test('maps PostgreSQL ${entry.key} to ${entry.value.name}', () async {
      final repository = SupabaseInventoryRepository(
        _client(
          MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': entry.key,
                'message': 'Injected database failure.',
                'details': null,
                'hint': null,
              }),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      await expectLater(
        repository.receive(
          ReceivingRequest(
            shopId: shopId,
            productId: productId,
            quantity: 20,
            expiryDate: LocalDate(2026, 9, 12),
            idempotencyKey: 'receive-1',
          ),
        ),
        throwsA(
          isA<InventoryRepositoryException>().having((error) => error.kind, 'kind', entry.value),
        ),
      );
    });
  }

  test('maps malformed RPC data without leaking a cast exception', () async {
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {...receiptJson, 'movement_batch_id': 'wrong-batch'},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.receive(
        ReceivingRequest(
          shopId: shopId,
          productId: productId,
          quantity: 20,
          expiryDate: LocalDate(2026, 9, 12),
          idempotencyKey: 'receive-1',
        ),
      ),
      throwsA(
        isA<InventoryRepositoryException>().having(
          (error) => error.kind,
          'kind',
          InventoryRepositoryFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('maps network failure to backend unavailable', () async {
    final repository = SupabaseInventoryRepository(
      _client(MockClient((request) async => throw http.ClientException('offline'))),
    );

    await expectLater(
      repository.receive(
        ReceivingRequest(
          shopId: shopId,
          productId: productId,
          quantity: 20,
          expiryDate: LocalDate(2026, 9, 12),
          idempotencyKey: 'receive-1',
        ),
      ),
      throwsA(
        isA<InventoryRepositoryException>().having(
          (error) => error.kind,
          'kind',
          InventoryRepositoryFailureKind.unavailable,
        ),
      ),
    );
  });
}

SupabaseClient _client(http.Client httpClient) {
  return SupabaseClient(
    'https://project.supabase.co',
    'sb_publishable_test-key',
    httpClient: httpClient,
    accessToken: () async => 'authenticated-user-token',
  );
}
