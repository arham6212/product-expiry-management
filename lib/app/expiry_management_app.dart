import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/authenticated_shop_gate.dart';
import '../features/inventory/application/receive_stock_controller.dart';
import '../features/product_resolution/application/product_resolution_controller.dart';
import '../features/shops/application/shop_session_controller.dart';
import '../features/storefront/application/public_storefront_controller.dart';
import '../features/storefront/application/storefront_management_controller.dart';
import '../features/storefront/presentation/explore_shops_page.dart';
import 'app_dependencies.dart';
import 'app_theme.dart';

class ExpiryManagementApp extends StatelessWidget {
  const ExpiryManagementApp({required this.environment, required this.dependencies, super.key});

  final AppEnvironment environment;
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(dependencies.authService),
        shopRepositoryProvider.overrideWithValue(dependencies.shopRepository),
        productCatalogRepositoryProvider.overrideWithValue(dependencies.productCatalogRepository),
        productLookupProviderProvider.overrideWithValue(dependencies.productLookupProvider),
        inventoryRepositoryProvider.overrideWithValue(dependencies.inventoryRepository),
        receiveStockProvider.overrideWithValue(dependencies.receiveStock),
        publicStorefrontRepositoryProvider.overrideWithValue(
          dependencies.publicStorefrontRepository,
        ),
        storefrontManagementRepositoryProvider.overrideWithValue(
          dependencies.storefrontManagementRepository,
        ),
      ],
      child: _ExpiryManagementView(environment: environment),
    );
  }
}

class _ExpiryManagementView extends StatelessWidget {
  const _ExpiryManagementView({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expiry Manager',
      debugShowCheckedModeBanner: environment.flavor != AppFlavor.production,
      theme: AppTheme.light,
      home: environment.enableStorefront
          ? const ExploreShopsPage()
          : const AuthenticatedShopGate(enableStorefront: false),
    );
  }
}
