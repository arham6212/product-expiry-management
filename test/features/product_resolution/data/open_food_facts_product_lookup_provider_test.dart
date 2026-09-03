import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_expiry_management/domain/ports/external_providers.dart';
import 'package:product_expiry_management/features/product_resolution/data/open_food_facts_product_lookup_provider.dart';

void main() {
  const barcode = '5000112519945';

  test('maps a valid product and requests only the required fields', () async {
    late http.Request captured;
    final provider = OpenFoodFactsProductLookupProvider(
      client: MockClient((request) async {
        captured = request;
        return http.Response(_foundBody(barcode: barcode), 200);
      }),
    );

    final result = await provider.findByBarcode(barcode);

    expect(result, isA<ProductLookupFound>());
    final candidate = (result as ProductLookupFound).candidate;
    expect(candidate.name, 'Coca Cola Zero 330ml');
    expect(candidate.brand, 'Coca-Cola');
    expect(candidate.imageUrl, Uri.parse('https://images.example.test/coke.jpg'));
    expect(candidate.providerReference, barcode);
    expect(captured.headers['user-agent'], contains('ProductExpiryManagement'));
    expect(captured.url.queryParameters['fields'], contains('image_front_url'));
    expect(captured.url.queryParameters['fields'], isNot(contains('ingredients')));
  });

  test('accepts a product without an image', () async {
    final provider = _providerFor(_foundBody(barcode: barcode, imageUrl: null));

    final result = await provider.findByBarcode(barcode) as ProductLookupFound;

    expect(result.candidate.imageUrl, isNull);
  });

  test('accepts a product without a brand', () async {
    final provider = _providerFor(_foundBody(barcode: barcode, brand: null));

    final result = await provider.findByBarcode(barcode) as ProductLookupFound;

    expect(result.candidate.brand, isNull);
  });

  test('uses generic name when product name is missing', () async {
    final provider = _providerFor(
      _foundBody(barcode: barcode, productName: null, genericName: 'Sparkling water'),
    );

    final result = await provider.findByBarcode(barcode) as ProductLookupFound;

    expect(result.candidate.name, 'Sparkling water');
  });

  test('does not accept a product without any usable name', () async {
    final provider = _providerFor(
      _foundBody(barcode: barcode, productName: null, genericName: null),
    );

    expect(await provider.findByBarcode(barcode), isA<ProductLookupNotFound>());
  });

  test('maps provider not-found as a valid not-found result', () async {
    final provider = _providerFor(
      jsonEncode({
        'status': 'failure',
        'result': {'id': 'product_not_found'},
        'code': barcode,
        'product': null,
      }),
      statusCode: 404,
    );

    expect(await provider.findByBarcode(barcode), isA<ProductLookupNotFound>());
  });

  test('maps malformed JSON without throwing', () async {
    final provider = _providerFor('{not-json');

    final result = await provider.findByBarcode(barcode) as ProductLookupUnavailable;

    expect(result.kind, ProductLookupFailureKind.malformed);
  });

  test('maps timeout without throwing', () async {
    final provider = OpenFoodFactsProductLookupProvider(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 1),
    );

    final result = await provider.findByBarcode(barcode) as ProductLookupUnavailable;

    expect(result.kind, ProductLookupFailureKind.timeout);
  });

  test('maps network error without throwing', () async {
    final provider = OpenFoodFactsProductLookupProvider(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    final result = await provider.findByBarcode(barcode) as ProductLookupUnavailable;

    expect(result.kind, ProductLookupFailureKind.network);
  });

  test('maps rate limit and server errors separately', () async {
    final rateLimited = await _providerFor('{}', statusCode: 429).findByBarcode(barcode);
    final serverError = await _providerFor('{}', statusCode: 503).findByBarcode(barcode);

    expect((rateLimited as ProductLookupUnavailable).kind, ProductLookupFailureKind.rateLimited);
    expect((serverError as ProductLookupUnavailable).kind, ProductLookupFailureKind.server);
  });
}

OpenFoodFactsProductLookupProvider _providerFor(String body, {int statusCode = 200}) {
  return OpenFoodFactsProductLookupProvider(
    client: MockClient((_) async => http.Response(body, statusCode)),
  );
}

String _foundBody({
  required String barcode,
  String? productName = '  Coca Cola   Zero 330ml ',
  String? genericName = '',
  String? brand = ' Coca-Cola ',
  String? imageUrl = 'https://images.example.test/coke.jpg',
}) {
  return jsonEncode({
    'status': 'success',
    'result': {'id': 'product_found'},
    'code': barcode,
    'product': {
      'code': barcode,
      'product_name': productName,
      'generic_name': genericName,
      'brands': brand,
      'quantity': '330 ml',
      'image_front_url': imageUrl,
    },
  });
}
