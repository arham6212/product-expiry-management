import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/features/shops/application/shop_invite_scan_controller.dart';

void main() {
  test('accepts one normalized invite and ignores duplicate callbacks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(shopInviteScanControllerProvider, (_, _) {});
    addTearDown(subscription.close);

    final controller = container.read(shopInviteScanControllerProvider.notifier);

    expect(controller.detect(' shop-invite:a1b2c3 '), 'A1B2C3');
    expect(controller.detect('shop-invite:Z9Y8X7'), isNull);
    expect(container.read(shopInviteScanControllerProvider).code, 'A1B2C3');
    expect(container.read(shopInviteScanControllerProvider).status, ShopInviteScanStatus.accepted);
  });

  test('malformed QR enters an invalid state and retry resumes scanning', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(shopInviteScanControllerProvider, (_, _) {});
    addTearDown(subscription.close);

    final controller = container.read(shopInviteScanControllerProvider.notifier);

    expect(controller.detect('https://example.test/not-an-invite'), isNull);
    expect(container.read(shopInviteScanControllerProvider).status, ShopInviteScanStatus.invalid);
    expect(controller.detect('shop-invite:A1B2C3'), isNull);

    controller.retry();

    expect(container.read(shopInviteScanControllerProvider).status, ShopInviteScanStatus.scanning);
    expect(controller.detect('shop-invite:A1B2C3'), 'A1B2C3');
  });
}
