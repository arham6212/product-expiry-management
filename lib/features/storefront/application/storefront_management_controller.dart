import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/storefront_models.dart';
import '../../inventory/application/receive_stock_controller.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import 'public_storefront_controller.dart';
import 'storefront_repository.dart';

final storefrontManagementRepositoryProvider = Provider<StorefrontManagementRepository>((ref) {
  throw StateError('storefrontManagementRepositoryProvider must be overridden at the app root.');
});

final storefrontManagementProvider =
    AsyncNotifierProvider.autoDispose<StorefrontManagementController, StorefrontManagementState>(
      StorefrontManagementController.new,
      retry: (retryCount, error) => null,
    );

final class StorefrontManagementState {
  const StorefrontManagementState({
    required this.shopId,
    required this.currencyCode,
    required this.profile,
    required this.products,
    required this.listings,
    required this.deals,
    this.isSaving = false,
    this.actionError,
  });

  final String shopId;
  final String currencyCode;
  final PublicShopProfile profile;
  final List<Product> products;
  final List<PublishedProductListing> listings;
  final List<Deal> deals;
  final bool isSaving;
  final String? actionError;

  PublishedProductListing? listingForProduct(String productId) {
    return listings.where((listing) => listing.productId == productId).firstOrNull;
  }

  List<Deal> dealsForListing(String listingId) {
    return deals.where((deal) => deal.listingId == listingId).toList(growable: false);
  }

  StorefrontManagementState copyWith({
    bool? isSaving,
    String? actionError,
    bool clearError = false,
  }) {
    return StorefrontManagementState(
      shopId: shopId,
      currencyCode: currencyCode,
      profile: profile,
      products: products,
      listings: listings,
      deals: deals,
      isSaving: isSaving ?? this.isSaving,
      actionError: clearError ? null : actionError ?? this.actionError,
    );
  }
}

final class StorefrontManagementController extends AsyncNotifier<StorefrontManagementState> {
  @override
  Future<StorefrontManagementState> build() async {
    final activeShop = ref.watch(activeShopProvider);
    if (activeShop == null) {
      throw const ShopAccessException('Select a shop before managing its storefront.');
    }
    if (activeShop.membership.role == ShopMembershipRole.worker) {
      throw const ShopAccessException('Only owners and managers can manage the public storefront.');
    }

    final shopId = activeShop.shop.id;
    final management = ref.watch(storefrontManagementRepositoryProvider);
    final results = await Future.wait<Object>([
      management.getShopProfile(shopId),
      ref.watch(inventoryRepositoryProvider).listProducts(shopId: shopId),
      management.listShopListings(shopId),
      management.listShopDeals(shopId),
    ]);
    return StorefrontManagementState(
      shopId: shopId,
      currencyCode: activeShop.shop.currencyCode,
      profile: results[0] as PublicShopProfile,
      products: results[1] as List<Product>,
      listings: results[2] as List<PublishedProductListing>,
      deals: results[3] as List<Deal>,
    );
  }

  void retry() => ref.invalidateSelf();

  Future<bool> saveProfile(PublicShopProfileDraft draft) {
    return _save((current, repository) => repository.saveShopProfile(current.shopId, draft));
  }

  Future<bool> saveListing(PublishedListingDraft draft) {
    return _save((current, repository) => repository.saveListing(current.shopId, draft));
  }

  Future<bool> saveDeal(DealDraft draft, {String? dealId}) {
    return _save(
      (current, repository) => repository.saveDeal(current.shopId, draft, dealId: dealId),
    );
  }

  Future<bool> setDealEnabled(Deal deal, bool enabled) {
    return _save(
      (current, repository) => repository.setDealEnabled(current.shopId, deal.id, enabled),
    );
  }

  Future<bool> _save(
    Future<Object> Function(
      StorefrontManagementState current,
      StorefrontManagementRepository repository,
    )
    operation,
  ) async {
    final current = state.requireValue;
    if (current.isSaving) return false;
    state = AsyncData(current.copyWith(isSaving: true, clearError: true));
    try {
      await operation(current, ref.read(storefrontManagementRepositoryProvider));
      if (!ref.mounted) return false;
      ref.invalidate(publicShopsProvider);
      ref.invalidate(publicStorefrontProvider(current.shopId));
      ref.invalidateSelf();
      await future;
      return true;
    } on StorefrontException catch (error) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(isSaving: false, actionError: error.message));
      }
    } on Object {
      if (ref.mounted) {
        state = AsyncData(
          current.copyWith(
            isSaving: false,
            actionError: 'The storefront change could not be saved. Please try again.',
          ),
        );
      }
    }
    return false;
  }
}
