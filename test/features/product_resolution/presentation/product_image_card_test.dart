import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_image_contribution.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_image_controller.dart';
import 'package:product_expiry_management/features/product_resolution/presentation/product_image_card.dart';

void main() {
  final jpeg = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  testWidgets('shows add action, gallery/camera choices, selection, and local remove', (
    tester,
  ) async {
    final picker = _Picker(RawProductImage(bytes: jpeg, filename: 'photo.jpg'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productImagePickerProvider.overrideWithValue(picker),
          productImageProcessorProvider.overrideWithValue(
            _Processor(
              ProcessedProductImage(bytes: jpeg, filename: 'photo.jpg', mimeType: 'image/jpeg'),
            ),
          ),
          productImageContributionRepositoryProvider.overrideWithValue(const _Repository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProductImageCard(shopId: 'shop-1', productId: 'catalog-1'),
          ),
        ),
      ),
    );
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.byKey(const Key('productImagePlaceholder')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chooseProductImageButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('takeProductPhotoOption')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chooseProductPhotoOption')));
    await tester.pumpAndSettle();
    expect(picker.lastSource, ProductImageSource.gallery);
    expect(find.byKey(const Key('selectedProductImage')), findsOneWidget);
    expect(find.byKey(const Key('removeSelectedProductImageButton')), findsNothing);
    expect(find.text('Saved to your shop'), findsOneWidget);
    expect(find.text('Pending review'), findsNothing);
    expect(find.text('Submitted'), findsNothing);
  });

  testWidgets('shop-only product does not offer a global contribution action', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProductImageCard(shopId: 'shop-1', productId: 'shop-only-product'),
          ),
        ),
      ),
    );
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.byKey(const Key('chooseProductImageButton')), findsOneWidget);
  });

  testWidgets('shows the canonical image and better-photo action when one exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productImagePickerProvider.overrideWithValue(
            _Picker(RawProductImage(bytes: jpeg, filename: 'photo.jpg')),
          ),
          productImageProcessorProvider.overrideWithValue(
            _Processor(
              ProcessedProductImage(bytes: jpeg, filename: 'photo.jpg', mimeType: 'image/jpeg'),
            ),
          ),
          productImageContributionRepositoryProvider.overrideWithValue(const _Repository()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProductImageCard(
              shopId: 'shop-1',
              productId: 'catalog-1',
              imageUrl: Uri.parse('https://example.test/product.jpg'),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('savedProductImage')), findsOneWidget);
    expect(find.text('Change photo'), findsOneWidget);
  });

  testWidgets('shows upload progress and disables resubmission after success', (tester) async {
    final upload = Completer<ProductImageContribution>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productImagePickerProvider.overrideWithValue(
            _Picker(RawProductImage(bytes: jpeg, filename: 'photo.jpg')),
          ),
          productImageProcessorProvider.overrideWithValue(
            _Processor(
              ProcessedProductImage(bytes: jpeg, filename: 'photo.jpg', mimeType: 'image/jpeg'),
            ),
          ),
          productImageContributionRepositoryProvider.overrideWithValue(
            _CompletingRepository(upload),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProductImageCard(shopId: 'shop-1', productId: 'catalog-1'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('chooseProductImageButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseProductPhotoOption')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('productImageUploadProgress')), findsOneWidget);

    upload.complete(
      ProductImageContribution(
        id: 'id',
        status: 'pending',
        deliveryUrl: Uri.parse('https://res.cloudinary.com/demo/image/upload/photo.jpg'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved to your shop'), findsOneWidget);
    expect(find.byKey(const Key('uploadProductImageButton')), findsNothing);
    expect(find.byKey(const Key('removeSelectedProductImageButton')), findsNothing);
  });
}

final class _Picker implements ProductImagePicker {
  _Picker(this.image);
  final RawProductImage image;
  ProductImageSource? lastSource;
  @override
  Future<RawProductImage?> pick(ProductImageSource source) async {
    lastSource = source;
    return image;
  }
}

final class _Processor implements ProductImageProcessor {
  const _Processor(this.image);
  final ProcessedProductImage image;
  @override
  Future<ProcessedProductImage> process(RawProductImage image) async => this.image;
}

final class _Repository implements ProductImageContributionRepository {
  const _Repository();
  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) async => ProductImageContribution(
    id: 'id',
    status: 'pending',
    deliveryUrl: Uri.parse('https://res.cloudinary.com/demo/image/upload/photo.jpg'),
  );
}

final class _CompletingRepository implements ProductImageContributionRepository {
  const _CompletingRepository(this.result);
  final Completer<ProductImageContribution> result;

  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) => result.future;
}
