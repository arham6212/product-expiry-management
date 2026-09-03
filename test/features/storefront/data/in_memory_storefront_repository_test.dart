import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';
import 'package:product_expiry_management/features/storefront/application/storefront_repository.dart';
import 'package:product_expiry_management/features/storefront/data/in_memory_storefront_repository.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);
  final publicShop = _profile('shop-public', true, now);
  final privateShop = _profile('shop-private', false, now);
  final published = _listing('listing-published', 'shop-public', 'product-1', true, now);
  final unpublished = _listing('listing-unpublished', 'shop-public', 'product-2', false, now);

  test('public reads include only enabled shops and published listings', () async {
    final repository = InMemoryStorefrontRepository(
      profiles: [publicShop, privateShop],
      listings: [published, unpublished],
      clock: () => now,
    );

    expect((await repository.listPublicShops()).map((shop) => shop.shopId), ['shop-public']);
    expect((await repository.listPublishedListings('shop-public')).map((item) => item.id), [
      'listing-published',
    ]);
    expect(await repository.getPublicShop('shop-private'), isNull);
  });

  test('active deal reads use repository clock and exclude future and expired deals', () async {
    final repository = InMemoryStorefrontRepository(
      profiles: [publicShop],
      listings: [published],
      deals: [
        _deal('active', now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1))),
        _deal('future', now.add(const Duration(hours: 2)), now.add(const Duration(hours: 3))),
        _deal(
          'expired',
          now.subtract(const Duration(hours: 3)),
          now.subtract(const Duration(hours: 2)),
        ),
      ],
      clock: () => now,
    );

    expect((await repository.listActiveDeals('shop-public')).map((deal) => deal.id), ['active']);
  });

  test('management rejects offer at or above normal price', () async {
    final repository = InMemoryStorefrontRepository(
      profiles: [publicShop],
      listings: [published],
      clock: () => now,
    );

    await expectLater(
      repository.saveDeal(
        'shop-public',
        DealDraft(
          listingId: published.id,
          offerPriceMinor: published.priceMinor,
          startsAt: now,
          endsAt: now.add(const Duration(days: 1)),
          isEnabled: true,
        ),
      ),
      throwsA(isA<StorefrontException>()),
    );
  });
}

PublicShopProfile _profile(String id, bool enabled, DateTime now) {
  return PublicShopProfile(
    shopId: id,
    displayName: id,
    isEnabled: enabled,
    createdAt: now,
    updatedAt: now,
  );
}

PublishedProductListing _listing(
  String id,
  String shopId,
  String productId,
  bool published,
  DateTime now,
) {
  return PublishedProductListing(
    id: id,
    shopId: shopId,
    productId: productId,
    displayName: id,
    priceMinor: 1000,
    currencyCode: 'QAR',
    isPublished: published,
    createdAt: now,
    updatedAt: now,
  );
}

Deal _deal(String id, DateTime startsAt, DateTime endsAt) {
  return Deal(
    id: id,
    shopId: 'shop-public',
    listingId: 'listing-published',
    offerPriceMinor: 800,
    startsAt: startsAt,
    endsAt: endsAt,
    isEnabled: true,
    createdAt: startsAt,
    updatedAt: startsAt,
  );
}
