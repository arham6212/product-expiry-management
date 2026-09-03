import '../../../core/identity/local_id_generator.dart';
import '../../../domain/entities/storefront_models.dart';
import '../application/storefront_repository.dart';

typedef StorefrontClock = DateTime Function();

final class InMemoryStorefrontRepository
    implements PublicStorefrontRepository, StorefrontManagementRepository {
  InMemoryStorefrontRepository({
    Iterable<PublicShopProfile> profiles = const [],
    Iterable<PublishedProductListing> listings = const [],
    Iterable<Deal> deals = const [],
    StorefrontClock? clock,
  }) : _profiles = {for (final profile in profiles) profile.shopId: profile},
       _listings = List.of(listings),
       _deals = List.of(deals),
       _clock = clock ?? _utcNow;

  final Map<String, PublicShopProfile> _profiles;
  final List<PublishedProductListing> _listings;
  final List<Deal> _deals;
  final StorefrontClock _clock;

  @override
  Future<List<PublicShopProfile>> listPublicShops() async {
    final result = _profiles.values.where((profile) => profile.isEnabled).toList()
      ..sort((left, right) => left.displayName.compareTo(right.displayName));
    return List.unmodifiable(result);
  }

  @override
  Future<PublicShopProfile?> getPublicShop(String shopId) async {
    final profile = _profiles[shopId];
    return profile?.isEnabled == true ? profile : null;
  }

  @override
  Future<List<PublishedProductListing>> listPublishedListings(String shopId) async {
    if (_profiles[shopId]?.isEnabled != true) return const [];
    return List.unmodifiable(
      _listings.where((listing) => listing.shopId == shopId && listing.isPublished).toList()
        ..sort((left, right) => left.displayName.compareTo(right.displayName)),
    );
  }

  @override
  Future<List<Deal>> listActiveDeals(String shopId) async {
    if (_profiles[shopId]?.isEnabled != true) return const [];
    final publishedIds = _listings
        .where((listing) => listing.shopId == shopId && listing.isPublished)
        .map((listing) => listing.id)
        .toSet();
    final now = _clock().toUtc();
    return List.unmodifiable(
      _deals.where(
        (deal) =>
            deal.shopId == shopId &&
            publishedIds.contains(deal.listingId) &&
            deal.isEnabled &&
            !deal.startsAt.isAfter(now) &&
            deal.endsAt.isAfter(now),
      ),
    );
  }

  @override
  Future<PublicShopProfile> getShopProfile(String shopId) async {
    final profile = _profiles[shopId];
    if (profile == null) throw const StorefrontException('Shop profile is unavailable.');
    return profile;
  }

  @override
  Future<List<PublishedProductListing>> listShopListings(String shopId) async {
    return List.unmodifiable(_listings.where((listing) => listing.shopId == shopId));
  }

  @override
  Future<List<Deal>> listShopDeals(String shopId) async {
    return List.unmodifiable(_deals.where((deal) => deal.shopId == shopId));
  }

  @override
  Future<PublicShopProfile> saveShopProfile(String shopId, PublicShopProfileDraft draft) async {
    final prior = _profiles[shopId];
    if (prior == null) throw const StorefrontException('Shop profile is unavailable.');
    final now = _clock().toUtc();
    final saved = PublicShopProfile(
      shopId: shopId,
      displayName: _required(draft.displayName, 'Shop display name'),
      description: _optional(draft.description),
      logoUrl: draft.logoUrl,
      area: _optional(draft.area),
      isEnabled: draft.isEnabled,
      createdAt: prior.createdAt,
      updatedAt: now,
    );
    _profiles[shopId] = saved;
    return saved;
  }

  @override
  Future<PublishedProductListing> saveListing(String shopId, PublishedListingDraft draft) async {
    final matches = _listings.indexWhere(
      (listing) => listing.shopId == shopId && listing.productId == draft.productId,
    );
    final prior = matches < 0 ? null : _listings[matches];
    final now = _clock().toUtc();
    final saved = PublishedProductListing(
      id: prior?.id ?? LocalIdGenerator.next('listing'),
      shopId: shopId,
      productId: draft.productId,
      displayName: _required(draft.displayName, 'Product display name'),
      description: _optional(draft.description),
      imageUrl: draft.imageUrl,
      priceMinor: draft.priceMinor,
      currencyCode: draft.currencyCode,
      isPublished: draft.isPublished,
      createdAt: prior?.createdAt ?? now,
      updatedAt: now,
    );
    if (matches < 0) {
      _listings.add(saved);
    } else {
      _listings[matches] = saved;
    }
    return saved;
  }

  @override
  Future<Deal> saveDeal(String shopId, DealDraft draft, {String? dealId}) async {
    final listing = _listings
        .where((candidate) => candidate.shopId == shopId && candidate.id == draft.listingId)
        .firstOrNull;
    if (listing == null) throw const StorefrontException('Published listing is unavailable.');
    if (draft.offerPriceMinor >= listing.priceMinor) {
      throw const StorefrontException('Offer price must be lower than the normal price.');
    }
    final now = _clock().toUtc();
    final index = dealId == null ? -1 : _deals.indexWhere((deal) => deal.id == dealId);
    final prior = index < 0 ? null : _deals[index];
    final saved = Deal(
      id: prior?.id ?? LocalIdGenerator.next('deal'),
      shopId: shopId,
      listingId: draft.listingId,
      offerPriceMinor: draft.offerPriceMinor,
      startsAt: draft.startsAt.toUtc(),
      endsAt: draft.endsAt.toUtc(),
      isEnabled: draft.isEnabled,
      title: _optional(draft.title),
      description: _optional(draft.description),
      createdAt: prior?.createdAt ?? now,
      updatedAt: now,
    );
    if (saved.isEnabled &&
        _deals.any(
          (deal) =>
              deal.id != saved.id &&
              deal.listingId == saved.listingId &&
              deal.isEnabled &&
              deal.startsAt.isBefore(saved.endsAt) &&
              deal.endsAt.isAfter(saved.startsAt),
        )) {
      throw const StorefrontException('Enabled deal dates cannot overlap.');
    }
    if (index < 0) {
      _deals.add(saved);
    } else {
      _deals[index] = saved;
    }
    return saved;
  }

  @override
  Future<Deal> setDealEnabled(String shopId, String dealId, bool isEnabled) async {
    final index = _deals.indexWhere((deal) => deal.shopId == shopId && deal.id == dealId);
    if (index < 0) throw const StorefrontException('Deal is unavailable.');
    final deal = _deals[index];
    return saveDeal(
      shopId,
      DealDraft(
        listingId: deal.listingId,
        offerPriceMinor: deal.offerPriceMinor,
        startsAt: deal.startsAt,
        endsAt: deal.endsAt,
        isEnabled: isEnabled,
        title: deal.title,
        description: deal.description,
      ),
      dealId: deal.id,
    );
  }
}

String _required(String value, String field) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) throw StorefrontException('$field is required.');
  return normalized;
}

String? _optional(String? value) {
  if (value == null) return null;
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? null : normalized;
}

DateTime _utcNow() => DateTime.now().toUtc();
