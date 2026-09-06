import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_image_contribution.dart';
import 'package:product_expiry_management/features/product_resolution/data/compressed_product_image_processor.dart';

void main() {
  final processor = CompressedProductImageProcessor();

  test('rejects content whose bytes are not JPEG, PNG, or WebP', () async {
    await expectLater(
      processor.process(
        RawProductImage(bytes: Uint8List.fromList(List<int>.filled(16, 0)), filename: 'photo.svg'),
      ),
      throwsA(
        isA<ProductImageException>().having(
          (error) => error.kind,
          'kind',
          ProductImageFailureKind.invalidType,
        ),
      ),
    );
  });

  test('rejects oversized input before invoking native compression', () async {
    final bytes = Uint8List(CompressedProductImageProcessor.maxInputBytes + 1)
      ..setAll(0, const [0xff, 0xd8, 0xff]);

    await expectLater(
      processor.process(RawProductImage(bytes: bytes, filename: 'large.jpg')),
      throwsA(
        isA<ProductImageException>().having(
          (error) => error.kind,
          'kind',
          ProductImageFailureKind.tooLarge,
        ),
      ),
    );
  });
}
