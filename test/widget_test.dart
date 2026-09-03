// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_dependencies.dart';
import 'package:product_expiry_management/app/expiry_management_app.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';
import 'package:product_expiry_management/features/storefront/application/storefront_repository.dart';

void main() {
  testWidgets('storefront enabled preserves Explore and Shop Operations', (tester) async {
    final environment = AppEnvironment.parse(
      flavor: 'development',
      supabaseUrl: 'https://project.supabase.co',
      supabasePublishableKey: 'sb_publishable_test-key',
      enableStorefront: 'true',
    );

    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Explore shops'), findsOneWidget);
    expect(find.text('Demo Shop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('openShopOperationsButton')));
    await tester.pumpAndSettle();

    expect(find.text('items need attention'), findsOneWidget);
  });

  testWidgets('storefront disabled starts in Shop Operations without a storefront query', (
    tester,
  ) async {
    final baseDependencies = AppDependencies.inMemory();
    final storefront = _RecordingPublicStorefrontRepository();
    final dependencies = AppDependencies(
      authService: baseDependencies.authService,
      shopRepository: baseDependencies.shopRepository,
      productCatalogRepository: baseDependencies.productCatalogRepository,
      productLookupProvider: baseDependencies.productLookupProvider,
      inventoryRepository: baseDependencies.inventoryRepository,
      receiveStock: baseDependencies.receiveStock,
      publicStorefrontRepository: storefront,
      storefrontManagementRepository: baseDependencies.storefrontManagementRepository,
    );
    final environment = AppEnvironment.parse(
      flavor: 'production',
      supabaseUrl: 'https://project.supabase.co',
      supabasePublishableKey: 'sb_publishable_test-key',
    );

    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: dependencies),
    );
    await tester.pumpAndSettle();

    expect(find.text('items need attention'), findsOneWidget);
    expect(find.text('Explore shops'), findsNothing);
    expect(storefront.queryCount, 0);

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('browsePublicShopsTile')), findsNothing);
    expect(find.byKey(const Key('manageStorefrontTile')), findsNothing);
  });
}

final class _RecordingPublicStorefrontRepository implements PublicStorefrontRepository {
  int queryCount = 0;

  @override
  Future<PublicShopProfile?> getPublicShop(String shopId) {
    queryCount += 1;
    throw StateError('Storefront query attempted while disabled.');
  }

  @override
  Future<List<Deal>> listActiveDeals(String shopId) {
    queryCount += 1;
    throw StateError('Storefront query attempted while disabled.');
  }

  @override
  Future<List<PublicShopProfile>> listPublicShops() {
    queryCount += 1;
    throw StateError('Storefront query attempted while disabled.');
  }

  @override
  Future<List<PublishedProductListing>> listPublishedListings(String shopId) {
    queryCount += 1;
    throw StateError('Storefront query attempted while disabled.');
  }
}
