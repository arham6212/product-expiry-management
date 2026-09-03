import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/storefront_models.dart';
import 'storefront_repository.dart';

final publicStorefrontRepositoryProvider = Provider<PublicStorefrontRepository>((ref) {
  throw StateError('publicStorefrontRepositoryProvider must be overridden at the app root.');
});

final publicShopsProvider = AsyncNotifierProvider<PublicShopsController, List<PublicShopProfile>>(
  PublicShopsController.new,
  retry: (retryCount, error) => null,
);

final publicStorefrontProvider = AsyncNotifierProvider.autoDispose
    .family<PublicStorefrontController, PublicStorefrontState, String>(
      PublicStorefrontController.new,
      retry: (retryCount, error) => null,
    );

final class PublicShopsController extends AsyncNotifier<List<PublicShopProfile>> {
  @override
  Future<List<PublicShopProfile>> build() {
    return ref.watch(publicStorefrontRepositoryProvider).listPublicShops();
  }

  void retry() => ref.invalidateSelf();
}

final class PublicStorefrontState {
  const PublicStorefrontState({
    required this.profile,
    required this.listings,
    required this.deals,
    this.query = '',
  });

  final PublicShopProfile profile;
  final List<PublishedProductListing> listings;
  final List<Deal> deals;
  final String query;

  List<PublishedProductListing> get visibleListings {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return listings;
    return listings
        .where(
          (listing) =>
              listing.displayName.toLowerCase().contains(normalized) ||
              (listing.description?.toLowerCase().contains(normalized) ?? false),
        )
        .toList(growable: false);
  }

  Deal? activeDealFor(String listingId) {
    return deals.where((deal) => deal.listingId == listingId).firstOrNull;
  }

  PublicStorefrontState copyWith({String? query}) {
    return PublicStorefrontState(
      profile: profile,
      listings: listings,
      deals: deals,
      query: query ?? this.query,
    );
  }
}

final class PublicStorefrontController extends AsyncNotifier<PublicStorefrontState> {
  PublicStorefrontController(this.shopId);

  final String shopId;

  @override
  Future<PublicStorefrontState> build() async {
    final repository = ref.watch(publicStorefrontRepositoryProvider);
    final results = await Future.wait<Object?>([
      repository.getPublicShop(shopId),
      repository.listPublishedListings(shopId),
      repository.listActiveDeals(shopId),
    ]);
    final profile = results[0] as PublicShopProfile?;
    if (profile == null) {
      throw const StorefrontException('This storefront is not available.');
    }
    return PublicStorefrontState(
      profile: profile,
      listings: results[1] as List<PublishedProductListing>,
      deals: results[2] as List<Deal>,
    );
  }

  void search(String query) {
    state = AsyncData(state.requireValue.copyWith(query: query));
  }

  void retry() => ref.invalidateSelf();
}
