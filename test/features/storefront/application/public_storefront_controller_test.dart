import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';
import 'package:product_expiry_management/features/storefront/application/public_storefront_controller.dart';
import 'package:product_expiry_management/features/storefront/data/in_memory_storefront_repository.dart';

void main() {
  test('public providers load without auth or CurrentShop overrides', () async {
    final now = DateTime.utc(2026, 9, 1);
    final repository = InMemoryStorefrontRepository(
      profiles: [
        PublicShopProfile(
          shopId: 'shop-1',
          displayName: 'Corner Shop',
          isEnabled: true,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      listings: [
        PublishedProductListing(
          id: 'listing-1',
          shopId: 'shop-1',
          productId: 'private-product-1',
          displayName: 'Fresh Milk',
          description: 'One litre',
          priceMinor: 700,
          currencyCode: 'QAR',
          isPublished: true,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      clock: () => now,
    );
    final container = ProviderContainer(
      overrides: [publicStorefrontRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    expect((await container.read(publicShopsProvider.future)).single.displayName, 'Corner Shop');
    final storefront = await container.read(publicStorefrontProvider('shop-1').future);
    expect(storefront.listings.single.displayName, 'Fresh Milk');

    container.read(publicStorefrontProvider('shop-1').notifier).search('missing');
    expect(
      container.read(publicStorefrontProvider('shop-1')).requireValue.visibleListings,
      isEmpty,
    );
  });
}
