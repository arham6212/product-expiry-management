import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/value_objects/normalized_barcode.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_catalog_repository.dart';
import 'package:product_expiry_management/features/product_resolution/data/supabase_product_catalog_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const shopId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const barcodeValue = '5000112519945';
  final productJson = <String, Object?>{
    'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'shop_id': shopId,
    'name': 'External Cola',
    'brand': 'Brand',
    'image_url': null,
    'source': 'open_food_facts',
    'source_reference': barcodeValue,
    'created_at': '2026-08-29T00:00:00Z',
    'updated_at': '2026-08-29T00:00:00Z',
  };

  test('queries the indexed shop/barcode mapping before returning Product', () async {
    late http.Request captured;
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {'products': productJson},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final product = await repository.findByBarcode(
      shopId: shopId,
      barcode: NormalizedBarcode.parse(barcodeValue),
    );

    expect(product?.name, 'External Cola');
    expect(product?.shopId, shopId);
    expect(captured.url.path, '/rest/v1/product_barcodes');
    expect(captured.url.queryParameters['shop_id'], 'eq.$shopId');
    expect(captured.url.queryParameters['barcode'], 'eq.$barcodeValue');
  });

  test('maps the atomic RPC outcome and sends normalized shop-owned input', () async {
    late http.Request captured;
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {...productJson, 'was_created': true},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.saveExternalProduct(
      shopId: shopId,
      barcode: NormalizedBarcode.parse(barcodeValue),
      product: const ExternalProductDraft(
        name: 'External Cola',
        brand: 'Brand',
        sourceReference: barcodeValue,
      ),
    );

    expect(result.wasCreated, isTrue);
    expect(result.product.source, ProductSource.openFoodFacts);
    expect(captured.url.path, '/rest/v1/rpc/create_product_for_barcode');
    final requestBody = jsonDecode(captured.body);
    expect(requestBody, isA<Map<String, dynamic>>());
    final body = requestBody as Map<String, dynamic>;
    expect(body['target_shop_id'], shopId);
    expect(body['normalized_barcode'], barcodeValue);
    expect(body['barcode_format'], 'ean13');
  });

  test('manual save uses the race-safe manual RPC and returns its persisted Product', () async {
    late http.Request captured;
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {
                ...productJson,
                'name': 'Manual Cola',
                'source': 'local_manual',
                'source_reference': null,
                'was_created': true,
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await repository.saveManualProduct(
      shopId: shopId,
      barcode: NormalizedBarcode.parse(barcodeValue),
      product: const ManualProductDraft(name: 'Manual Cola', brand: 'Local Brand'),
    );

    expect(result.product.name, 'Manual Cola');
    expect(result.product.source, ProductSource.localManual);
    expect(captured.url.path, '/rest/v1/rpc/create_manual_product_for_barcode');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['target_shop_id'], shopId);
    expect(body['normalized_barcode'], barcodeValue);
    expect(body['product_name'], 'Manual Cola');
    expect(body['product_brand'], 'Local Brand');
  });

  test('creates only a normalized local Product without a barcode request', () async {
    late http.Request captured;
    var requestCount = 0;
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient((request) async {
          requestCount += 1;
          captured = request;
          return http.Response(
            jsonEncode({
              ...productJson,
              'name': 'Fresh milk',
              'brand': 'Local Dairy',
              'source': 'local_manual',
              'source_reference': null,
            }),
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final product = await repository.createManualProductWithoutBarcode(
      shopId: ' $shopId ',
      product: const ManualProductDraft(name: ' Fresh   milk ', brand: ' Local   Dairy '),
    );

    expect(product.name, 'Fresh milk');
    expect(product.brand, 'Local Dairy');
    expect(product.source, ProductSource.localManual);
    expect(product.sourceReference, isNull);
    expect(product.catalogProductId, isNull);
    expect(requestCount, 1);
    expect(captured.url.path, '/rest/v1/products');
    expect(captured.method, 'POST');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body, {
      'shop_id': shopId,
      'name': 'Fresh milk',
      'brand': 'Local Dairy',
      'source': 'local_manual',
    });
  });

  test('rejects invalid barcode-less input before making a request', () async {
    var requestCount = 0;
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient((request) async {
          requestCount += 1;
          return http.Response('{}', 500, request: request);
        }),
      ),
    );

    await expectLater(
      repository.createManualProductWithoutBarcode(
        shopId: shopId,
        product: const ManualProductDraft(name: '   '),
      ),
      throwsA(isA<ProductCatalogException>()),
    );
    expect(requestCount, 0);
  });

  test('rejects a created barcode-less Product from another shop', () async {
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              ...productJson,
              'shop_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              'name': 'Manual product',
              'brand': null,
              'source': 'local_manual',
              'source_reference': null,
            }),
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.createManualProductWithoutBarcode(
        shopId: shopId,
        product: const ManualProductDraft(name: 'Manual product'),
      ),
      throwsA(isA<ProductCatalogException>()),
    );
  });

  test('rejects unexpected identity metadata in the created Product', () async {
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              ...productJson,
              'name': 'Manual product',
              'brand': null,
              'source': 'local_manual',
              'source_reference': 'guessed-reference',
            }),
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    await expectLater(
      repository.createManualProductWithoutBarcode(
        shopId: shopId,
        product: const ManualProductDraft(name: 'Manual product'),
      ),
      throwsA(isA<ProductCatalogException>()),
    );
  });

  test('rejects an RPC Product response from another shop', () async {
    final repository = SupabaseProductCatalogRepository(
      _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                ...productJson,
                'shop_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
                'was_created': true,
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
      repository.saveExternalProduct(
        shopId: shopId,
        barcode: NormalizedBarcode.parse(barcodeValue),
        product: const ExternalProductDraft(name: 'External Cola', sourceReference: barcodeValue),
      ),
      throwsA(isA<ProductCatalogException>()),
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
