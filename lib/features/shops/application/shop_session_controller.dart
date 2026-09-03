import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/shop_invite_qr.dart';
import '../../auth/application/auth_controller.dart';
import 'shop_access.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  throw StateError('shopRepositoryProvider must be overridden at the application root.');
});

final shopSessionControllerProvider =
    AsyncNotifierProvider<ShopSessionController, ShopSessionState>(
      ShopSessionController.new,
      retry: (retryCount, error) => null,
    );

final activeShopProvider = Provider<ShopAccess?>((ref) {
  return switch (ref.watch(shopSessionControllerProvider)) {
    AsyncData(:final value) => value.activeShop,
    _ => null,
  };
});

final class ShopSessionState {
  const ShopSessionState({
    this.shops = const [],
    this.activeShop,
    this.isChoosingShop = false,
    this.isCreatingShop = false,
    this.isJoiningShop = false,
    this.actionError,
    this.pendingRequest,
    this.scannedInviteCode,
  });

  final List<ShopAccess> shops;
  final ShopAccess? activeShop;
  final bool isChoosingShop;
  final bool isCreatingShop;
  final bool isJoiningShop;
  final String? actionError;
  final ShopJoinRequest? pendingRequest;
  final String? scannedInviteCode;

  ShopSessionState copyWith({
    List<ShopAccess>? shops,
    ShopAccess? activeShop,
    bool clearActiveShop = false,
    bool? isChoosingShop,
    bool? isCreatingShop,
    bool? isJoiningShop,
    String? actionError,
    bool clearActionError = false,
    ShopJoinRequest? pendingRequest,
    bool clearPendingRequest = false,
    String? scannedInviteCode,
    bool clearScannedInviteCode = false,
  }) {
    return ShopSessionState(
      shops: shops ?? this.shops,
      activeShop: clearActiveShop ? null : activeShop ?? this.activeShop,
      isChoosingShop: isChoosingShop ?? this.isChoosingShop,
      isCreatingShop: isCreatingShop ?? this.isCreatingShop,
      isJoiningShop: isJoiningShop ?? this.isJoiningShop,
      actionError: clearActionError ? null : actionError ?? this.actionError,
      pendingRequest: clearPendingRequest ? null : pendingRequest ?? this.pendingRequest,
      scannedInviteCode: clearScannedInviteCode
          ? null
          : scannedInviteCode ?? this.scannedInviteCode,
    );
  }
}

final class ShopSessionController extends AsyncNotifier<ShopSessionState> {
  @override
  Future<ShopSessionState> build() async {
    final user = await ref.watch(authUserProvider.future);
    if (user == null) return const ShopSessionState();

    final repo = ref.watch(shopRepositoryProvider);
    final shops = await repo.listForCurrentUser();

    if (shops.isNotEmpty) {
      // 1-shop-per-user model
      return ShopSessionState(shops: shops, activeShop: shops.first);
    }

    // Check if user has a pending request
    final pendingRequest = await repo.getMyPendingRequest();

    return ShopSessionState(shops: shops, pendingRequest: pendingRequest);
  }

  void retry() => ref.invalidateSelf();

  void selectScannedInviteCode(String code) {
    final current = state.requireValue;
    final normalizedCode = ShopInviteQr.normalizeCode(code);
    if (!ShopInviteQr.isValidCode(normalizedCode)) return;
    state = AsyncData(current.copyWith(scannedInviteCode: normalizedCode, clearActionError: true));
  }

  void clearScannedInviteCode() {
    final current = state.requireValue;
    if (current.scannedInviteCode == null) return;
    state = AsyncData(current.copyWith(clearScannedInviteCode: true));
  }

  void chooseAnotherShop() {
    final current = state.requireValue;
    if (current.shops.length < 2) return;
    state = AsyncData(current.copyWith(isChoosingShop: true, clearActionError: true));
  }

  void selectShop(ShopAccess access) {
    final current = state.requireValue;
    final selected = current.shops.where((candidate) => candidate.shop.id == access.shop.id);
    if (selected.isEmpty) return;
    state = AsyncData(
      current.copyWith(activeShop: selected.single, isChoosingShop: false, clearActionError: true),
    );
  }

  Future<void> createFirstShop(String name) async {
    final current = state.requireValue;
    if (current.isCreatingShop) return;
    if (name.trim().isEmpty) {
      state = AsyncData(current.copyWith(actionError: 'Enter a shop name.'));
      return;
    }

    state = AsyncData(current.copyWith(isCreatingShop: true, clearActionError: true));
    try {
      final access = await ref.read(shopRepositoryProvider).createShopWithOwner(name);
      if (!ref.mounted) return;
      state = AsyncData(ShopSessionState(shops: [access], activeShop: access));
    } on ShopAccessException catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isCreatingShop: false, actionError: error.message));
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(
          isCreatingShop: false,
          actionError: 'The shop could not be created. Check the connection and try again.',
        ),
      );
    }
  }

  Future<void> requestToJoinShop(String code) async {
    final current = state.requireValue;
    if (current.isJoiningShop) return;
    final normalizedCode = ShopInviteQr.normalizeCode(code);
    if (normalizedCode.isEmpty) {
      state = AsyncData(current.copyWith(actionError: 'Enter an invite code.'));
      return;
    }

    state = AsyncData(current.copyWith(isJoiningShop: true, clearActionError: true));
    try {
      final repo = ref.read(shopRepositoryProvider);
      await repo.requestToJoinShop(normalizedCode);
      final pendingRequest = await repo.getMyPendingRequest();
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isJoiningShop: false, pendingRequest: pendingRequest));
    } on ShopAccessException catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isJoiningShop: false, actionError: error.message));
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(
          isJoiningShop: false,
          actionError: 'Could not join shop. Check connection and try again.',
        ),
      );
    }
  }
}
