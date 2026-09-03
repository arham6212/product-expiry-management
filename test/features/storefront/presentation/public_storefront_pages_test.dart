import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';
import 'package:product_expiry_management/features/storefront/application/public_storefront_controller.dart';
import 'package:product_expiry_management/features/storefront/data/in_memory_storefront_repository.dart';
import 'package:product_expiry_management/features/storefront/presentation/explore_shops_page.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);
  final profile = PublicShopProfile(
    shopId: 'shop-1',
    displayName: 'Corner Bakala',
    description: 'Neighbourhood essentials.',
    area: 'Al Sadd',
    isEnabled: true,
    createdAt: now,
    updatedAt: now,
  );
  final listing = PublishedProductListing(
    id: 'listing-1',
    shopId: profile.shopId,
    productId: 'private-product-1',
    displayName: 'Fresh Milk',
    description: 'One litre',
    priceMinor: 700,
    currencyCode: 'QAR',
    isPublished: true,
    createdAt: now,
    updatedAt: now,
  );
  final deal = Deal(
    id: 'deal-1',
    shopId: profile.shopId,
    listingId: listing.id,
    offerPriceMinor: 550,
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 1)),
    isEnabled: true,
    title: 'Milk deal',
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('anonymous customer explores a shop, sees deal, searches, and opens details', (
    tester,
  ) async {
    final repository = InMemoryStorefrontRepository(
      profiles: [profile],
      listings: [listing],
      deals: [deal],
      clock: () => now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [publicStorefrontRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ExploreShopsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Corner Bakala'), findsOneWidget);
    await tester.tap(find.text('Corner Bakala'));
    await tester.pumpAndSettle();

    expect(find.text('Deals'), findsOneWidget);
    expect(find.text('Milk deal'), findsOneWidget);
    expect(find.text('QAR 5.50'), findsWidgets);
    expect(find.text('Fresh Milk'), findsWidgets);

    await tester.enterText(find.byKey(const Key('publicProductSearchField')), 'coffee');
    await tester.pump();
    expect(find.byKey(const Key('productSearchEmptyState')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('publicProductSearchField')), 'milk');
    await tester.pump();
    await tester.tap(find.text('Fresh Milk').last);
    await tester.pumpAndSettle();

    expect(find.text('Product details'), findsOneWidget);
    expect(find.textContaining('Availability is not guaranteed'), findsOneWidget);
  });

  testWidgets('empty storefront and no-deals states are explicit', (tester) async {
    final repository = InMemoryStorefrontRepository(profiles: [profile], clock: () => now);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [publicStorefrontRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ExploreShopsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corner Bakala'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noDealsState')), findsOneWidget);
    expect(find.byKey(const Key('emptyStorefrontState')), findsOneWidget);
  });
}
