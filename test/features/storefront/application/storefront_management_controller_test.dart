import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';
import 'package:product_expiry_management/features/inventory/application/receive_stock_controller.dart';
import 'package:product_expiry_management/features/inventory/data/in_memory_inventory_repository.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';
import 'package:product_expiry_management/features/storefront/application/storefront_management_controller.dart';
import 'package:product_expiry_management/features/storefront/application/storefront_repository.dart';
import 'package:product_expiry_management/features/storefront/data/in_memory_storefront_repository.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1);
  final product = Product(
    id: 'product-1',
    shopId: 'shop-1',
    name: 'Milk',
    createdAt: now,
    updatedAt: now,
  );
  final profile = PublicShopProfile(
    shopId: 'shop-1',
    displayName: 'Shop 1',
    isEnabled: false,
    createdAt: now,
    updatedAt: now,
  );

  for (final role in [ShopMembershipRole.owner, ShopMembershipRole.manager]) {
    test('${role.name} can load storefront management', () async {
      final container = _container(role, product, profile, now);
      addTearDown(container.dispose);

      final state = await container.read(storefrontManagementProvider.future);

      expect(state.products.single.id, product.id);
      expect(state.profile.isEnabled, isFalse);
    });
  }

  test('worker is rejected before management repository access', () async {
    final container = _container(ShopMembershipRole.worker, product, profile, now);
    addTearDown(container.dispose);

    await expectLater(
      container.read(storefrontManagementProvider.future),
      throwsA(isA<ShopAccessException>()),
    );
  });

  test('owner publishes a Product, creates a deal, and deactivates it', () async {
    final storefront = InMemoryStorefrontRepository(profiles: [profile], clock: () => now);
    final container = _container(
      ShopMembershipRole.owner,
      product,
      profile,
      now,
      storefront: storefront,
    );
    addTearDown(container.dispose);
    await container.read(storefrontManagementProvider.future);
    final controller = container.read(storefrontManagementProvider.notifier);

    expect(
      await controller.saveListing(
        const PublishedListingDraft(
          productId: 'product-1',
          displayName: 'Public Milk',
          priceMinor: 700,
          currencyCode: 'QAR',
          isPublished: true,
        ),
      ),
      isTrue,
    );
    final listing = container.read(storefrontManagementProvider).requireValue.listings.single;
    expect(
      await controller.saveDeal(
        DealDraft(
          listingId: listing.id,
          offerPriceMinor: 500,
          startsAt: now,
          endsAt: now.add(const Duration(days: 1)),
          isEnabled: true,
          title: 'Launch deal',
        ),
      ),
      isTrue,
    );
    final deal = container.read(storefrontManagementProvider).requireValue.deals.single;
    expect(await controller.setDealEnabled(deal, false), isTrue);
    expect(
      container.read(storefrontManagementProvider).requireValue.deals.single.isEnabled,
      isFalse,
    );
  });
}

ProviderContainer _container(
  ShopMembershipRole role,
  Product product,
  PublicShopProfile profile,
  DateTime now, {
  InMemoryStorefrontRepository? storefront,
}) {
  final repository =
      storefront ?? InMemoryStorefrontRepository(profiles: [profile], clock: () => now);
  return ProviderContainer(
    overrides: [
      activeShopProvider.overrideWithValue(
        ShopAccess(
          shop: Shop(
            id: 'shop-1',
            name: 'Shop 1',
            timeZone: 'Asia/Qatar',
            currencyCode: 'QAR',
            createdAt: now,
            updatedAt: now,
          ),
          membership: ShopMembership(
            shopId: 'shop-1',
            userId: 'user-1',
            role: role,
            createdAt: now,
          ),
        ),
      ),
      inventoryRepositoryProvider.overrideWithValue(
        InMemoryInventoryRepository(products: [product]),
      ),
      storefrontManagementRepositoryProvider.overrideWithValue(repository),
    ],
  );
}
