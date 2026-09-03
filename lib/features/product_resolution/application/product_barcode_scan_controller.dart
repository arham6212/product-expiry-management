import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/value_objects/normalized_barcode.dart';

final productBarcodeScanControllerProvider =
    NotifierProvider.autoDispose<ProductBarcodeScanController, ProductBarcodeScanState>(
      ProductBarcodeScanController.new,
    );

enum ProductBarcodeScanStatus { scanning, invalid, accepted }

final class ProductBarcodeScanState {
  const ProductBarcodeScanState({
    this.status = ProductBarcodeScanStatus.scanning,
    this.barcode,
    this.message,
  });

  final ProductBarcodeScanStatus status;
  final String? barcode;
  final String? message;
}

final class ProductBarcodeScanController extends Notifier<ProductBarcodeScanState> {
  @override
  ProductBarcodeScanState build() => const ProductBarcodeScanState();

  String? detect(String rawValue) {
    if (state.status != ProductBarcodeScanStatus.scanning) return null;

    try {
      final barcode = NormalizedBarcode.parse(rawValue);
      state = ProductBarcodeScanState(
        status: ProductBarcodeScanStatus.accepted,
        barcode: barcode.value,
      );
      return barcode.value;
    } on BarcodeValidationException catch (error) {
      state = ProductBarcodeScanState(
        status: ProductBarcodeScanStatus.invalid,
        message: error.message,
      );
      return null;
    }
  }

  void retry() => state = const ProductBarcodeScanState();
}
