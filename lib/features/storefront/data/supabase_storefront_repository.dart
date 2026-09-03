import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/storefront_models.dart';
import '../application/storefront_repository.dart';

final class SupabaseStorefrontRepository
    implements PublicStorefrontRepository, StorefrontManagementRepository {
  const SupabaseStorefrontRepository(this._client);

  final SupabaseClient _client;

  static const _profileFields =
      'shop_id,display_name,description,logo_url,area,is_enabled,created_at,updated_at';
  static const _publicListingFields =
      'id,shop_id,display_name,description,image_url,price_minor,'
      'currency_code,is_published,created_at,updated_at';
  static const _managementListingFields =
      'id,shop_id,product_id,display_name,description,image_url,price_minor,'
      'currency_code,is_published,created_at,updated_at';
  static const _dealFields =
      'id,shop_id,listing_id,offer_price_minor,starts_at,ends_at,is_enabled,'
      'title,description,created_at,updated_at';

  @override
  Future<List<PublicShopProfile>> listPublicShops() async {
    try {
      final rows = await _client
          .from('public_storefront_shops')
          .select(_profileFields)
          .order('display_name');
      return List.unmodifiable(rows.map(_mapProfile));
    } on PostgrestException catch (error) {
      throw StorefrontException('Public shops could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('Public shops returned invalid data.', cause: error);
    }
  }

  @override
  Future<PublicShopProfile?> getPublicShop(String shopId) async {
    try {
      final rows = await _client
          .from('public_storefront_shops')
          .select(_profileFields)
          .eq('shop_id', shopId)
          .limit(1);
      return rows.isEmpty ? null : _mapProfile(rows.single);
    } on PostgrestException catch (error) {
      throw StorefrontException('The storefront could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('The storefront returned invalid data.', cause: error);
    }
  }

  @override
  Future<List<PublishedProductListing>> listPublishedListings(String shopId) async {
    try {
      final rows = await _client
          .from('public_storefront_listings')
          .select(_publicListingFields)
          .eq('shop_id', shopId)
          .order('display_name');
      return List.unmodifiable(rows.map(_mapListing));
    } on PostgrestException catch (error) {
      throw StorefrontException('Products could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('Products returned invalid data.', cause: error);
    }
  }

  @override
  Future<List<Deal>> listActiveDeals(String shopId) async {
    try {
      // RLS evaluates enabled/window/listing/storefront visibility with
      // PostgreSQL now(); the client deliberately supplies no clock filter.
      final rows = await _client
          .from('public_storefront_deals')
          .select(_dealFields)
          .eq('shop_id', shopId)
          .order('starts_at');
      return List.unmodifiable(rows.map(_mapDeal));
    } on PostgrestException catch (error) {
      throw StorefrontException('Deals could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('Deals returned invalid data.', cause: error);
    }
  }

  @override
  Future<PublicShopProfile> getShopProfile(String shopId) async {
    try {
      final rows = await _client
          .from('public_shop_profiles')
          .select(_profileFields)
          .eq('shop_id', shopId)
          .limit(1);
      if (rows.isEmpty) throw const StorefrontException('Shop profile is unavailable.');
      return _mapProfile(rows.single);
    } on PostgrestException catch (error) {
      throw StorefrontException('Shop profile could not be loaded.', cause: error);
    } on StorefrontException {
      rethrow;
    } on Object catch (error) {
      throw StorefrontException('Shop profile returned invalid data.', cause: error);
    }
  }

  @override
  Future<List<PublishedProductListing>> listShopListings(String shopId) async {
    try {
      final rows = await _client
          .from('published_product_listings')
          .select(_managementListingFields)
          .eq('shop_id', shopId)
          .order('display_name');
      return List.unmodifiable(rows.map(_mapListing));
    } on PostgrestException catch (error) {
      throw StorefrontException('Shop listings could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('Shop listings returned invalid data.', cause: error);
    }
  }

  @override
  Future<List<Deal>> listShopDeals(String shopId) async {
    try {
      final rows = await _client
          .from('deals')
          .select(_dealFields)
          .eq('shop_id', shopId)
          .order('starts_at', ascending: false);
      return List.unmodifiable(rows.map(_mapDeal));
    } on PostgrestException catch (error) {
      throw StorefrontException('Shop deals could not be loaded.', cause: error);
    } on Object catch (error) {
      throw StorefrontException('Shop deals returned invalid data.', cause: error);
    }
  }

  @override
  Future<PublicShopProfile> saveShopProfile(String shopId, PublicShopProfileDraft draft) async {
    try {
      final row = await _client
          .from('public_shop_profiles')
          .upsert({
            'shop_id': shopId,
            'display_name': _required(draft.displayName, 'Shop display name'),
            'description': _optional(draft.description),
            'logo_url': draft.logoUrl?.toString(),
            'area': _optional(draft.area),
            'is_enabled': draft.isEnabled,
          }, onConflict: 'shop_id')
          .select(_profileFields)
          .single();
      return _mapProfile(row);
    } on PostgrestException catch (error) {
      throw StorefrontException(_message(error, 'Shop profile could not be saved.'), cause: error);
    } on StorefrontException {
      rethrow;
    } on Object catch (error) {
      throw StorefrontException('Shop profile returned invalid data.', cause: error);
    }
  }

  @override
  Future<PublishedProductListing> saveListing(String shopId, PublishedListingDraft draft) async {
    try {
      final row = await _client
          .from('published_product_listings')
          .upsert({
            'shop_id': shopId,
            'product_id': draft.productId,
            'display_name': _required(draft.displayName, 'Product display name'),
            'description': _optional(draft.description),
            'image_url': draft.imageUrl?.toString(),
            'price_minor': draft.priceMinor,
            'currency_code': draft.currencyCode,
            'is_published': draft.isPublished,
          }, onConflict: 'shop_id,product_id')
          .select(_managementListingFields)
          .single();
      return _mapListing(row);
    } on PostgrestException catch (error) {
      throw StorefrontException(
        _message(error, 'Product listing could not be saved.'),
        cause: error,
      );
    } on StorefrontException {
      rethrow;
    } on Object catch (error) {
      throw StorefrontException('Product listing returned invalid data.', cause: error);
    }
  }

  @override
  Future<Deal> saveDeal(String shopId, DealDraft draft, {String? dealId}) async {
    final values = <String, Object?>{
      'shop_id': shopId,
      'listing_id': draft.listingId,
      'offer_price_minor': draft.offerPriceMinor,
      'starts_at': draft.startsAt.toUtc().toIso8601String(),
      'ends_at': draft.endsAt.toUtc().toIso8601String(),
      'is_enabled': draft.isEnabled,
      'title': _optional(draft.title),
      'description': _optional(draft.description),
    };
    try {
      final Map<String, dynamic> row;
      if (dealId == null) {
        row = await _client.from('deals').insert(values).select(_dealFields).single();
      } else {
        row = await _client
            .from('deals')
            .update(values)
            .eq('shop_id', shopId)
            .eq('id', dealId)
            .select(_dealFields)
            .single();
      }
      return _mapDeal(row);
    } on PostgrestException catch (error) {
      throw StorefrontException(_message(error, 'Deal could not be saved.'), cause: error);
    } on StorefrontException {
      rethrow;
    } on Object catch (error) {
      throw StorefrontException('Deal returned invalid data.', cause: error);
    }
  }

  @override
  Future<Deal> setDealEnabled(String shopId, String dealId, bool isEnabled) async {
    try {
      final row = await _client
          .from('deals')
          .update({'is_enabled': isEnabled})
          .eq('shop_id', shopId)
          .eq('id', dealId)
          .select(_dealFields)
          .single();
      return _mapDeal(row);
    } on PostgrestException catch (error) {
      throw StorefrontException(_message(error, 'Deal status could not be saved.'), cause: error);
    } on Object catch (error) {
      throw StorefrontException('Deal status returned invalid data.', cause: error);
    }
  }
}

PublicShopProfile _mapProfile(Map<String, dynamic> row) {
  return PublicShopProfile(
    shopId: _string(row, 'shop_id'),
    displayName: _string(row, 'display_name'),
    description: _nullableString(row, 'description'),
    logoUrl: _uri(row, 'logo_url'),
    area: _nullableString(row, 'area'),
    isEnabled: _bool(row, 'is_enabled'),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );
}

PublishedProductListing _mapListing(Map<String, dynamic> row) {
  return PublishedProductListing(
    id: _string(row, 'id'),
    shopId: _string(row, 'shop_id'),
    productId: _nullableString(row, 'product_id'),
    displayName: _string(row, 'display_name'),
    description: _nullableString(row, 'description'),
    imageUrl: _uri(row, 'image_url'),
    priceMinor: _int(row, 'price_minor'),
    currencyCode: _string(row, 'currency_code'),
    isPublished: _bool(row, 'is_published'),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );
}

Deal _mapDeal(Map<String, dynamic> row) {
  return Deal(
    id: _string(row, 'id'),
    shopId: _string(row, 'shop_id'),
    listingId: _string(row, 'listing_id'),
    offerPriceMinor: _int(row, 'offer_price_minor'),
    startsAt: _date(row, 'starts_at'),
    endsAt: _date(row, 'ends_at'),
    isEnabled: _bool(row, 'is_enabled'),
    title: _nullableString(row, 'title'),
    description: _nullableString(row, 'description'),
    createdAt: _date(row, 'created_at'),
    updatedAt: _date(row, 'updated_at'),
  );
}

String _string(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key.');
  return value;
}

String? _nullableString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

Uri? _uri(Map<String, dynamic> row, String key) {
  final value = _nullableString(row, key);
  return value == null ? null : Uri.parse(value);
}

int _int(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! int) throw FormatException('Invalid $key.');
  return value;
}

bool _bool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! bool) throw FormatException('Invalid $key.');
  return value;
}

DateTime _date(Map<String, dynamic> row, String key) {
  return DateTime.parse(_string(row, key)).toUtc();
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

String _message(PostgrestException error, String fallback) {
  return switch (error.code) {
    '42501' => 'Only an owner or manager can make this storefront change.',
    '23P01' => 'This deal overlaps another enabled deal for the product.',
    '22023' => error.message,
    _ => fallback,
  };
}
