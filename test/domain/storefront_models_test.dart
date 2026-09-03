import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_validation_exception.dart';
import 'package:product_expiry_management/domain/entities/storefront_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1);

  test('listing requires positive minor-unit price and valid currency', () {
    expect(
      () => PublishedProductListing(
        id: 'listing-1',
        shopId: 'shop-1',
        productId: 'product-1',
        displayName: 'Milk',
        priceMinor: 0,
        currencyCode: 'QAR',
        isPublished: true,
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('deal requires a forward time window', () {
    expect(
      () => Deal(
        id: 'deal-1',
        shopId: 'shop-1',
        listingId: 'listing-1',
        offerPriceMinor: 500,
        startsAt: now,
        endsAt: now,
        isEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('public profile accepts only HTTP image URLs', () {
    expect(
      () => PublicShopProfile(
        shopId: 'shop-1',
        displayName: 'Shop',
        logoUrl: Uri.parse('file:///private/logo.png'),
        isEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });
}
