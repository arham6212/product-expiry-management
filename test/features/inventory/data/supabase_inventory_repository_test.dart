import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/services/expiry_risk_service.dart';
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
  final dashboardJson = <String, Object?>{
    'reference_date': '2026-09-03',
    'shop_id': shopId,
    'batch_id': batchId,
    'product_id': productId,
    'product_name': 'Milk',
    'product_brand': 'Pilot Brand',
    'expiry_date': '2026-09-02',
    'days_to_expiry': -1,
    'current_quantity': 5,
    'lot_number': 'LOT-7',
    'received_at': '2026-08-30T10:00:00Z',
  };

  test('reads unknown quantity without hiding the expiry row', () async {
    final repository = _dashboardRepository([
      {...dashboardJson, 'current_quantity': null},
    ]);
    final snapshot = await repository.loadExpiryDashboard(shopId: shopId);
    expect(snapshot.items.single.currentQuantity, isNull);
    expect(snapshot.items.single.quantityLabel, 'Unknown');
  });

  test('sends JSON null and maps an audited unknown-quantity receipt', () async {
    late http.Request captured;
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {...receiptJson, 'batch_current_quantity': null, 'movement_quantity_delta': null},
            ]),
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
        sellingPriceMinor: 725,
        expiryDate: LocalDate(2026, 9, 12),
        lotNumber: 'LOT-7',
        idempotencyKey: 'receive-1',
      ),
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.containsKey('received_quantity'), isTrue);
    expect(body['received_quantity'], isNull);
    expect(receipt.batch.currentQuantity, isNull);
    expect(receipt.movement.quantityDelta, isNull);
  });

  test('maps the dashboard RPC contract and sends the selected Shop ID', () async {
    late http.Request captured;
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([dashboardJson]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final snapshot = await repository.loadExpiryDashboard(shopId: shopId);
    final item = snapshot.items.single;

    expect(snapshot.referenceDate, LocalDate(2026, 9, 3));
    expect(item.shopId, shopId);
    expect(item.batchId, batchId);
    expect(item.productId, productId);
    expect(item.productName, 'Milk');
    expect(item.productBrand, 'Pilot Brand');
    expect(item.expiryDate, LocalDate(2026, 9, 2));
    expect(item.daysToExpiry, -1);
    expect(item.riskCategory, ExpiryRiskCategory.expired);
    expect(item.currentQuantity, 5);
    expect(item.lotNumber, 'LOT-7');
    expect(item.receivedAt, DateTime.utc(2026, 8, 30, 10));
    expect(captured.url.path, '/rest/v1/rpc/get_expiry_dashboard');
    expect((jsonDecode(captured.body) as Map<String, dynamic>)['target_shop_id'], shopId);
  });

  for (final boundary in <({int days, ExpiryRiskCategory category})>[
    (days: 0, category: ExpiryRiskCategory.expiresToday),
    (days: 7, category: ExpiryRiskCategory.next7Days),
    (days: 8, category: ExpiryRiskCategory.days8To30),
    (days: 30, category: ExpiryRiskCategory.days8To30),
    (days: 31, category: ExpiryRiskCategory.later),
  ]) {
    test('classifies a dashboard row at +${boundary.days} through B08', () async {
      final reference = DateTime.utc(2026, 9, 3);
      final expiry = reference.add(Duration(days: boundary.days));
      final repository = SupabaseInventoryRepository(
        _client(
          MockClient(
            (request) async => http.Response(
              jsonEncode([
                {
                  ...dashboardJson,
                  'expiry_date': LocalDate(expiry.year, expiry.month, expiry.day).toString(),
                  'days_to_expiry': boundary.days,
                },
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      final snapshot = await repository.loadExpiryDashboard(shopId: shopId);

      expect(snapshot.items.single.riskCategory, boundary.category);
      expect(snapshot.items.single.daysToExpiry, boundary.days);
    });
  }

  test('preserves unknown expiry and nullable display fields', () async {
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                ...dashboardJson,
                'product_brand': null,
                'expiry_date': null,
                'days_to_expiry': null,
                'lot_number': null,
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final item = (await repository.loadExpiryDashboard(shopId: shopId)).items.single;

    expect(item.productBrand, isNull);
    expect(item.expiryDate, isNull);
    expect(item.daysToExpiry, isNull);
    expect(item.riskCategory, isNull);
    expect(item.lotNumber, isNull);
  });

  test('maps B09 empty metadata to a typed empty snapshot', () async {
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                'reference_date': '2026-09-03',
                'shop_id': shopId,
                'batch_id': null,
                'product_id': null,
                'product_name': null,
                'product_brand': null,
                'expiry_date': null,
                'days_to_expiry': null,
                'current_quantity': null,
                'lot_number': null,
                'received_at': null,
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final snapshot = await repository.loadExpiryDashboard(shopId: shopId);

    expect(snapshot.referenceDate, LocalDate(2026, 9, 3));
    expect(snapshot.items, isEmpty);
  });

  test('rejects a dashboard row from another Shop', () async {
    final repository = _dashboardRepository([
      {...dashboardJson, 'shop_id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'},
    ]);

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
    );
  });

  for (final malformed in <({String name, Map<String, Object?> row})>[
    (name: 'reference date', row: {...dashboardJson, 'reference_date': '03/09/2026'}),
    (name: 'expiry date', row: {...dashboardJson, 'expiry_date': 'not-a-date'}),
    (name: 'Batch ID', row: {...dashboardJson, 'batch_id': 'not-a-uuid'}),
    (name: 'Product ID type', row: {...dashboardJson, 'product_id': 42}),
    (name: 'quantity type', row: {...dashboardJson, 'current_quantity': '5'}),
    (name: 'non-positive quantity', row: {...dashboardJson, 'current_quantity': 0}),
    (name: 'received timestamp', row: {...dashboardJson, 'received_at': '2026-08-30T10:00:00'}),
  ]) {
    test('rejects malformed dashboard ${malformed.name}', () async {
      final repository = _dashboardRepository([malformed.row]);

      await expectLater(
        repository.loadExpiryDashboard(shopId: shopId),
        throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
      );
    });
  }

  test('rejects a server day offset inconsistent with the authoritative dates', () async {
    final repository = _dashboardRepository([
      {...dashboardJson, 'days_to_expiry': 30},
    ]);

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
    );
  });

  test('rejects rows with inconsistent authoritative reference dates', () async {
    final repository = _dashboardRepository([
      dashboardJson,
      {
        ...dashboardJson,
        'reference_date': '2026-09-04',
        'batch_id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      },
    ]);

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
    );
  });

  test('rejects an empty RPC response without B09 reference metadata', () async {
    final repository = _dashboardRepository([]);

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
    );
  });

  test('rejects a dashboard row with a missing contract field', () async {
    final missingBrand = Map<String, Object?>.of(dashboardJson)..remove('product_brand');
    final repository = _dashboardRepository([missingBrand]);

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidResponse)),
    );
  });

  test('rejects an invalid requested Shop ID before RPC I/O', () async {
    var called = false;
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient((request) async {
          called = true;
          return http.Response('[]', 200, request: request);
        }),
      ),
    );

    await expectLater(
      repository.loadExpiryDashboard(shopId: 'not-a-uuid'),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.invalidInput)),
    );
    expect(called, isFalse);
  });

  test('maps dashboard authorization errors through repository semantics', () async {
    final repository = SupabaseInventoryRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'Shop membership is required.',
              'details': null,
              'hint': null,
            }),
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.authorization)),
    );
  });

  test('maps dashboard network failure to backend unavailable', () async {
    final repository = SupabaseInventoryRepository(
      _client(MockClient((request) async => throw http.ClientException('offline'))),
    );

    await expectLater(
      repository.loadExpiryDashboard(shopId: shopId),
      throwsA(_repositoryFailure(InventoryRepositoryFailureKind.unavailable)),
    );
  });

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
        sellingPriceMinor: 725,
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
    expect(body['target_selling_price_minor'], 725);
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
          sellingPriceMinor: 725,
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
                'catalog_product_id': null,
                'selling_price_minor': 725,
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
    expect(products.single.sellingPriceMinor, 725);
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
            sellingPriceMinor: 725,
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
          sellingPriceMinor: 725,
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
          sellingPriceMinor: 725,
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

SupabaseInventoryRepository _dashboardRepository(List<Map<String, Object?>> rows) {
  return SupabaseInventoryRepository(
    _client(
      MockClient(
        (request) async => http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    ),
  );
}

Matcher _repositoryFailure(InventoryRepositoryFailureKind kind) {
  return isA<InventoryRepositoryException>().having((error) => error.kind, 'kind', kind);
}
