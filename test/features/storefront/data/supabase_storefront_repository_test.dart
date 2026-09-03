import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:product_expiry_management/features/storefront/application/storefront_repository.dart';
import 'package:product_expiry_management/features/storefront/data/supabase_storefront_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const shopId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final dealJson = <String, Object?>{
    'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'shop_id': shopId,
    'listing_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'offer_price_minor': 500,
    'starts_at': '2026-09-01T10:00:00Z',
    'ends_at': '2026-09-02T10:00:00Z',
    'is_enabled': true,
    'title': 'Deal',
    'description': null,
    'created_at': '2026-09-01T09:00:00Z',
    'updated_at': '2026-09-01T09:00:00Z',
  };

  test('active deal query relies on RLS/server time and sends no client time filter', () async {
    late http.Request captured;
    final repository = SupabaseStorefrontRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([dealJson]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final deals = await repository.listActiveDeals(shopId);

    expect(deals.single.title, 'Deal');
    expect(captured.url.path, '/rest/v1/public_storefront_deals');
    expect(captured.url.queryParameters['shop_id'], 'eq.$shopId');
    expect(captured.url.queryParameters, isNot(contains('starts_at')));
    expect(captured.url.queryParameters, isNot(contains('ends_at')));
  });

  test('listing save uses shop/product upsert and public-only payload', () async {
    late http.Request captured;
    final listingJson = <String, Object?>{
      'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'shop_id': shopId,
      'product_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
      'display_name': 'Public Milk',
      'description': null,
      'image_url': null,
      'price_minor': 700,
      'currency_code': 'QAR',
      'is_published': true,
      'created_at': '2026-09-01T09:00:00Z',
      'updated_at': '2026-09-01T09:00:00Z',
    };
    final repository = SupabaseStorefrontRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(listingJson),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final listing = await repository.saveListing(
      shopId,
      const PublishedListingDraft(
        productId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        displayName: 'Public Milk',
        priceMinor: 700,
        currencyCode: 'QAR',
        isPublished: true,
      ),
    );

    expect(listing.displayName, 'Public Milk');
    expect(captured.url.path, '/rest/v1/published_product_listings');
    expect(captured.url.queryParameters['on_conflict'], 'shop_id,product_id');
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload.keys, isNot(contains('current_quantity')));
    expect(payload.keys, isNot(contains('expiry_date')));
    expect(payload.keys, isNot(contains('purchase_cost')));
  });

  test('customer listing projection omits the private Product identifier', () async {
    late http.Request captured;
    final publicListing = <String, Object?>{
      'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'shop_id': shopId,
      'display_name': 'Public Milk',
      'description': null,
      'image_url': null,
      'price_minor': 700,
      'currency_code': 'QAR',
      'is_published': true,
      'created_at': '2026-09-01T09:00:00Z',
      'updated_at': '2026-09-01T09:00:00Z',
    };
    final repository = SupabaseStorefrontRepository(
      _client(
        MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([publicListing]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final listing = (await repository.listPublishedListings(shopId)).single;

    expect(listing.productId, isNull);
    expect(captured.url.path, '/rest/v1/public_storefront_listings');
    expect(captured.url.queryParameters['select'], isNot(contains('product_id')));
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
