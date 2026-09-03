import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/features/product_resolution/application/product_barcode_scan_controller.dart';

void main() {
  test('accepts and normalizes a supported retail barcode once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(productBarcodeScanControllerProvider.notifier);

    expect(controller.detect('  5000112519945  '), '5000112519945');
    expect(controller.detect('12345670'), isNull);
    expect(
      container.read(productBarcodeScanControllerProvider).status,
      ProductBarcodeScanStatus.accepted,
    );
  });

  test('rejects an unsupported scan and retry enables scanning again', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(productBarcodeScanControllerProvider.notifier);

    expect(controller.detect('shop-invite:ABC123'), isNull);
    expect(
      container.read(productBarcodeScanControllerProvider).status,
      ProductBarcodeScanStatus.invalid,
    );

    controller.retry();

    expect(controller.detect('5000112519945'), '5000112519945');
  });
}
