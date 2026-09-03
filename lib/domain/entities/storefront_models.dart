import 'domain_validation_exception.dart';

final class CatalogProduct {
  CatalogProduct({
    required this.id,
    required this.canonicalName,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.brand,
    this.imageUrl,
    this.sourceReference,
  }) {
    _requireText(id, 'id');
    _requireText(canonicalName, 'canonicalName');
  }

  final String id;
  final String canonicalName;
  final String? brand;
  final Uri? imageUrl;
  final String source;
  final String? sourceReference;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class PublicShopProfile {
  PublicShopProfile({
    required this.shopId,
    required this.displayName,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.logoUrl,
    this.area,
  }) {
    _requireText(shopId, 'shopId');
    _requireText(displayName, 'displayName');
    _requireHttpUrl(logoUrl, 'logoUrl');
  }

  final String shopId;
  final String displayName;
  final String? description;
  final Uri? logoUrl;
  final String? area;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class PublishedProductListing {
  PublishedProductListing({
    required this.id,
    required this.shopId,
    required this.displayName,
    required this.priceMinor,
    required this.currencyCode,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
    this.productId,
    this.description,
    this.imageUrl,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    if (productId != null) _requireText(productId!, 'productId');
    _requireText(displayName, 'displayName');
    if (priceMinor <= 0) {
      throw const DomainValidationException('priceMinor must be greater than zero.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      throw const DomainValidationException('currencyCode must be a three-letter code.');
    }
    _requireHttpUrl(imageUrl, 'imageUrl');
  }

  final String id;
  final String shopId;

  /// Present for authorized management reads; deliberately absent from the
  /// customer projection, which uses the public listing ID.
  final String? productId;
  final String displayName;
  final String? description;
  final Uri? imageUrl;
  final int priceMinor;
  final String currencyCode;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class Deal {
  Deal({
    required this.id,
    required this.shopId,
    required this.listingId,
    required this.offerPriceMinor,
    required this.startsAt,
    required this.endsAt,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.description,
  }) {
    _requireText(id, 'id');
    _requireText(shopId, 'shopId');
    _requireText(listingId, 'listingId');
    if (offerPriceMinor <= 0) {
      throw const DomainValidationException('offerPriceMinor must be greater than zero.');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw const DomainValidationException('endsAt must be after startsAt.');
    }
  }

  final String id;
  final String shopId;
  final String listingId;
  final int offerPriceMinor;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isEnabled;
  final String? title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
}

void _requireText(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw DomainValidationException('$fieldName must not be empty.');
  }
}

void _requireHttpUrl(Uri? value, String fieldName) {
  if (value == null) return;
  if (!value.hasAuthority || (value.scheme != 'http' && value.scheme != 'https')) {
    throw DomainValidationException('$fieldName must be an absolute HTTP or HTTPS URL.');
  }
}
