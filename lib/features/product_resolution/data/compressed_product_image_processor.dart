import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../application/product_image_contribution.dart';

final class CompressedProductImageProcessor implements ProductImageProcessor {
  static const maxInputBytes = 20 * 1024 * 1024;
  static const maxOutputBytes = 5 * 1024 * 1024;

  @override
  Future<ProcessedProductImage> process(RawProductImage image) async {
    if (!_hasAllowedSignature(image.bytes)) {
      throw const ProductImageException(
        ProductImageFailureKind.invalidType,
        'Choose a JPEG, PNG, or WebP image.',
      );
    }
    if (image.bytes.isEmpty || image.bytes.length > maxInputBytes) {
      throw const ProductImageException(
        ProductImageFailureKind.tooLarge,
        'That photo is too large. Choose one under 20 MB.',
      );
    }
    var output = await _compress(image.bytes, 82);
    if (output.length > maxOutputBytes) output = await _compress(image.bytes, 62);
    if (output.isEmpty || output.length > maxOutputBytes) {
      throw const ProductImageException(
        ProductImageFailureKind.tooLarge,
        'The photo could not be reduced below 5 MB. Choose a smaller image.',
      );
    }
    return ProcessedProductImage(
      bytes: output,
      filename: 'product-photo.jpg',
      mimeType: 'image/jpeg',
    );
  }

  Future<Uint8List> _compress(Uint8List bytes, int quality) async =>
      FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 2048,
        minHeight: 2048,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

  bool _hasAllowedSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47;
    final webp =
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return jpeg || png || webp;
  }
}
