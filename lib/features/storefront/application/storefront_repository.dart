import '../../../domain/entities/storefront_models.dart';

final class StorefrontException implements Exception {
  const StorefrontException(this.message, {this.cause});

  final String message;
  final Object? cause;
}

final class PublicShopProfileDraft {
  const PublicShopProfileDraft({
    required this.displayName,
    required this.isEnabled,
    this.description,
    this.logoUrl,
    this.area,
  });

  final String displayName;
  final String? description;
  final Uri? logoUrl;
  final String? area;
  final bool isEnabled;
}

final class PublishedListingDraft {
  const PublishedListingDraft({
    required this.productId,
    required this.displayName,
    required this.priceMinor,
    required this.currencyCode,
    required this.isPublished,
    this.description,
    this.imageUrl,
  });

  final String productId;
  final String displayName;
  final String? description;
  final Uri? imageUrl;
  final int priceMinor;
  final String currencyCode;
  final bool isPublished;
}

final class DealDraft {
  const DealDraft({
    required this.listingId,
    required this.offerPriceMinor,
    required this.startsAt,
    required this.endsAt,
    required this.isEnabled,
    this.title,
    this.description,
  });

  final String listingId;
  final int offerPriceMinor;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isEnabled;
  final String? title;
  final String? description;
}

abstract interface class PublicStorefrontRepository {
  Future<List<PublicShopProfile>> listPublicShops();

  Future<PublicShopProfile?> getPublicShop(String shopId);

  Future<List<PublishedProductListing>> listPublishedListings(String shopId);

  /// Persistence is responsible for using server time to exclude inactive,
  /// future, and expired deals.
  Future<List<Deal>> listActiveDeals(String shopId);
}

abstract interface class StorefrontManagementRepository {
  Future<PublicShopProfile> getShopProfile(String shopId);

  Future<List<PublishedProductListing>> listShopListings(String shopId);

  Future<List<Deal>> listShopDeals(String shopId);

  Future<PublicShopProfile> saveShopProfile(String shopId, PublicShopProfileDraft draft);

  Future<PublishedProductListing> saveListing(String shopId, PublishedListingDraft draft);

  Future<Deal> saveDeal(String shopId, DealDraft draft, {String? dealId});

  Future<Deal> setDealEnabled(String shopId, String dealId, bool isEnabled);
}
