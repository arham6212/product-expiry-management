import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../../domain/ports/external_providers.dart';

final class OpenFoodFactsProductLookupProvider implements ProductLookupProvider {
  OpenFoodFactsProductLookupProvider({
    required http.Client client,
    this.timeout = const Duration(seconds: 8),
    Uri? endpoint,
  }) : _client = client,
       _endpoint = endpoint ?? Uri.parse('https://world.openfoodfacts.org/api/v3.6/product/');

  static const _fields = <String>[
    'code',
    'product_name',
    'generic_name',
    'brands',
    'quantity',
    'image_front_url',
  ];

  final http.Client _client;
  final Duration timeout;
  final Uri _endpoint;

  @override
  Future<ProductLookupResult> findByBarcode(String barcode) async {
    final uri = _endpoint
        .resolve('$barcode.json')
        .replace(queryParameters: {'fields': _fields.join(',')});

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              if (!kIsWeb) 'User-Agent': 'ProductExpiryManagement/0.1 (Flutter client)',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      return const ProductLookupUnavailable(ProductLookupFailureKind.timeout);
    } on http.ClientException {
      return const ProductLookupUnavailable(ProductLookupFailureKind.network);
    } on Object {
      return const ProductLookupUnavailable(ProductLookupFailureKind.unknown);
    }

    if (response.statusCode == 429) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.rateLimited);
    }
    if (response.statusCode >= 500) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.server);
    }
    if (response.statusCode != 200 && response.statusCode != 404) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.unknown);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const ProductLookupUnavailable(ProductLookupFailureKind.malformed);
    }
    if (decoded is! Map<String, dynamic>) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.malformed);
    }

    final result = decoded['result'];
    final resultId = result is Map<String, dynamic> ? _string(result['id']) : null;
    if (response.statusCode == 404 || resultId == 'product_not_found') {
      return const ProductLookupNotFound();
    }
    if (decoded['status'] != 'success' || resultId != 'product_found') {
      return const ProductLookupUnavailable(ProductLookupFailureKind.malformed);
    }

    final productValue = decoded['product'];
    if (productValue is! Map<String, dynamic>) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.malformed);
    }
    final returnedBarcode = _normalizeText(
      _string(productValue['code']) ?? _string(decoded['code']),
    );
    if (returnedBarcode != barcode) {
      return const ProductLookupUnavailable(ProductLookupFailureKind.malformed);
    }

    final name =
        _normalizeText(_string(productValue['product_name'])) ??
        _normalizeText(_string(productValue['generic_name']));
    if (name == null) {
      return const ProductLookupNotFound();
    }

    return ProductLookupFound(
      ProductLookupCandidate(
        barcode: barcode,
        name: name,
        brand: _normalizeText(_string(productValue['brands'])),
        imageUrl: _httpUri(_string(productValue['image_front_url'])),
        providerReference: barcode,
      ),
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

String? _normalizeText(String? value) {
  if (value == null) return null;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}

Uri? _httpUri(String? value) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
