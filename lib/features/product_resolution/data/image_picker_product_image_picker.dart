import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/product_image_contribution.dart';

final class ImagePickerProductImagePicker implements ProductImagePicker {
  ImagePickerProductImagePicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<RawProductImage?> pick(ProductImageSource source) async {
    try {
      XFile? file;
      final lost = await _picker.retrieveLostData();
      if (lost.exception != null) throw lost.exception!;
      if (!lost.isEmpty && lost.files != null && lost.files!.isNotEmpty) file = lost.files!.first;
      file ??= await _picker.pickImage(
        source: source == ProductImageSource.camera ? ImageSource.camera : ImageSource.gallery,
      );
      if (file == null) return null;
      return RawProductImage(bytes: await file.readAsBytes(), filename: file.name);
    } on PlatformException catch (error) {
      final denied = error.code.contains('access_denied') || error.code.contains('permission');
      throw ProductImageException(
        denied ? ProductImageFailureKind.permissionDenied : ProductImageFailureKind.upload,
        denied
            ? 'Photo access was denied. Enable it in device settings and try again.'
            : 'The photo picker could not be opened.',
        cause: error,
      );
    }
  }
}
