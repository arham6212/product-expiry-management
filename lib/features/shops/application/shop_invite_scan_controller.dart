import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/shop_invite_qr.dart';

final shopInviteScanControllerProvider =
    NotifierProvider.autoDispose<ShopInviteScanController, ShopInviteScanState>(
      ShopInviteScanController.new,
    );

enum ShopInviteScanStatus { scanning, invalid, accepted }

final class ShopInviteScanState {
  const ShopInviteScanState({this.status = ShopInviteScanStatus.scanning, this.code});

  final ShopInviteScanStatus status;
  final String? code;
}

final class ShopInviteScanController extends Notifier<ShopInviteScanState> {
  @override
  ShopInviteScanState build() => const ShopInviteScanState();

  String? detect(String rawValue) {
    if (state.status != ShopInviteScanStatus.scanning) return null;

    final code = ShopInviteQr.parse(rawValue);
    if (code == null) {
      state = const ShopInviteScanState(status: ShopInviteScanStatus.invalid);
      return null;
    }

    state = ShopInviteScanState(status: ShopInviteScanStatus.accepted, code: code);
    return code;
  }

  void retry() {
    state = const ShopInviteScanState();
  }
}
