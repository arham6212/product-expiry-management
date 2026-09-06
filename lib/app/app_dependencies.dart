import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/identity/secure_id_generator.dart';
import '../domain/entities/domain_models.dart';
import '../domain/entities/storefront_models.dart';
import '../domain/value_objects/local_date.dart';
import '../features/auth/application/auth_service.dart';
import '../features/auth/data/in_memory_auth_service.dart';
import '../features/auth/data/supabase_auth_service.dart';
import '../features/inventory/application/receive_stock.dart';
import '../features/inventory/data/in_memory_inventory_repository.dart';
import '../features/inventory/data/supabase_inventory_repository.dart';
import '../features/product_resolution/application/product_catalog_repository.dart';
import '../features/product_resolution/application/product_image_contribution.dart';
import '../features/product_resolution/data/compressed_product_image_processor.dart';
import '../features/product_resolution/data/image_picker_product_image_picker.dart';
import '../features/product_resolution/data/in_memory_product_catalog_repository.dart';
import '../features/product_resolution/data/supabase_cloudinary_product_image_repository.dart';
import '../features/product_resolution/data/supabase_product_catalog_repository.dart';
import '../features/product_resolution/data/unavailable_product_image_repository.dart';
import '../features/shops/application/shop_access.dart';
import '../features/shops/data/in_memory_shop_repository.dart';
import '../features/shops/data/supabase_shop_repository.dart';
import '../features/storefront/application/storefront_repository.dart';
import '../features/storefront/data/in_memory_storefront_repository.dart';
import '../features/storefront/data/supabase_storefront_repository.dart';

final class AppDependencies {
  const AppDependencies({
    required this.authService,
    required this.shopRepository,
    required this.productCatalogRepository,
    required this.inventoryRepository,
    required this.receiveStock,
    required this.publicStorefrontRepository,
    required this.storefrontManagementRepository,
    this.productImageContributionRepository = const UnavailableProductImageRepository(),
    this.productImagePicker,
    this.productImageProcessor,
  });

  factory AppDependencies.inMemory() {
    final seededAt = DateTime.utc(2026, 8, 29);
    final milk = Product(
      id: 'product-almarai-milk-1l',
      shopId: 'shop-demo',
      name: 'Almarai Milk 1L',
      brand: 'Almarai',
      category: 'Dairy',
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final yogurt = Product(
      id: 'product-plain-yogurt',
      shopId: 'shop-demo',
      name: 'Plain Yogurt 500g',
      category: 'Dairy',
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final existingBatch = Batch(
      id: 'batch-existing-milk',
      shopId: milk.shopId,
      productId: milk.id,
      expiryDate: LocalDate(2026, 9, 3),
      currentQuantity: 5,
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final existingMovement = InventoryMovement(
      id: 'movement-existing-milk',
      shopId: milk.shopId,
      batchId: existingBatch.id,
      type: InventoryMovementType.received,
      quantityDelta: 5,
      occurredAt: seededAt,
      createdAt: seededAt,
      idempotencyKey: 'seed-existing-milk',
    );
    final inventoryRepository = InMemoryInventoryRepository(
      products: [milk, yogurt],
      batches: [existingBatch],
      movements: [existingMovement],
      expiryDashboardReferenceDate: LocalDate(2026, 9, 1),
    );
    const user = AuthenticatedUser(id: 'user-demo', email: 'demo@example.test');
    final shop = Shop(
      id: 'shop-demo',
      name: 'Demo Shop',
      timeZone: 'Asia/Qatar',
      currencyCode: 'QAR',
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final access = ShopAccess(
      shop: shop,
      membership: ShopMembership(
        shopId: shop.id,
        userId: user.id,
        role: ShopMembershipRole.owner,
        createdAt: seededAt,
      ),
    );
    final invite = ShopInvite(
      id: 'invite-demo',
      shopId: shop.id,
      code: 'DEMO01',
      isActive: true,
      createdAt: seededAt,
      createdBy: user.id,
      expiresAt: DateTime.utc(2030),
    );
    final barcode = ProductBarcode(
      id: 'barcode-almarai-milk',
      shopId: milk.shopId,
      productId: milk.id,
      value: '6281007000062',
      format: BarcodeFormat.ean13,
      isPrimary: true,
      createdAt: seededAt,
    );
    final publicProfile = PublicShopProfile(
      shopId: shop.id,
      displayName: shop.name,
      description: 'Everyday groceries from your neighbourhood shop.',
      area: 'Doha',
      isEnabled: true,
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final milkListing = PublishedProductListing(
      id: 'listing-almarai-milk',
      shopId: shop.id,
      productId: milk.id,
      displayName: milk.name,
      description: 'Fresh full-fat milk, 1 litre.',
      priceMinor: 700,
      currencyCode: 'QAR',
      isPublished: true,
      createdAt: seededAt,
      updatedAt: seededAt,
    );
    final storefrontRepository = InMemoryStorefrontRepository(
      profiles: [publicProfile],
      listings: [milkListing],
      deals: [
        Deal(
          id: 'deal-almarai-milk',
          shopId: shop.id,
          listingId: milkListing.id,
          offerPriceMinor: 550,
          startsAt: DateTime.utc(2026, 8, 1),
          endsAt: DateTime.utc(2030),
          isEnabled: true,
          title: 'Weekly deal',
          createdAt: seededAt,
          updatedAt: seededAt,
        ),
      ],
      clock: () => DateTime.utc(2026, 9, 1),
    );

    return AppDependencies(
      authService: InMemoryAuthService(currentUser: user),
      shopRepository: InMemoryShopRepository(userId: user.id, shops: [access], invites: [invite]),
      productCatalogRepository: InMemoryProductCatalogRepository(
        products: [milk, yogurt],
        barcodes: [barcode],
      ),
      inventoryRepository: inventoryRepository,
      receiveStock: ReceiveStock(
        repository: inventoryRepository,
        idempotencyKeyGenerator: SecureIdGenerator.uuidV4,
      ),
      publicStorefrontRepository: storefrontRepository,
      storefrontManagementRepository: storefrontRepository,
      productImagePicker: ImagePickerProductImagePicker(),
      productImageProcessor: CompressedProductImageProcessor(),
    );
  }

  factory AppDependencies.supabase(SupabaseClient client) {
    final inventoryRepository = SupabaseInventoryRepository(client);
    final storefrontRepository = SupabaseStorefrontRepository(client);
    return AppDependencies(
      authService: SupabaseAuthService(client),
      shopRepository: SupabaseShopRepository(client),
      productCatalogRepository: SupabaseProductCatalogRepository(client),
      inventoryRepository: inventoryRepository,
      receiveStock: ReceiveStock(
        repository: inventoryRepository,
        idempotencyKeyGenerator: SecureIdGenerator.uuidV4,
      ),
      publicStorefrontRepository: storefrontRepository,
      storefrontManagementRepository: storefrontRepository,
      productImageContributionRepository: SupabaseCloudinaryProductImageRepository(client),
      productImagePicker: ImagePickerProductImagePicker(),
      productImageProcessor: CompressedProductImageProcessor(),
    );
  }

  final AuthService authService;
  final ShopRepository shopRepository;
  final ProductCatalogRepository productCatalogRepository;
  final InventoryRepository inventoryRepository;
  final ReceiveStock receiveStock;
  final PublicStorefrontRepository publicStorefrontRepository;
  final StorefrontManagementRepository storefrontManagementRepository;
  final ProductImageContributionRepository productImageContributionRepository;
  final ProductImagePicker? productImagePicker;
  final ProductImageProcessor? productImageProcessor;
}
