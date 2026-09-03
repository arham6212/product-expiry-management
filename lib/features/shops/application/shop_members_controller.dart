import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/domain_models.dart';
import '../../auth/application/auth_controller.dart';
import 'shop_access.dart';
import 'shop_session_controller.dart';

final shopMembersControllerProvider =
    AsyncNotifierProvider.autoDispose<ShopMembersController, ShopMembersState>(
      ShopMembersController.new,
      retry: (retryCount, error) => null,
    );

final class ShopMembersState {
  const ShopMembersState({
    this.members = const [],
    this.pendingRequests = const [],
    this.activeInvite,
    this.actionError,
    this.isProcessingAction = false,
  });

  final List<ShopMemberProfile> members;
  final List<PendingRequestProfile> pendingRequests;
  final ShopInvite? activeInvite;
  final String? actionError;
  final bool isProcessingAction;

  ShopMembersState copyWith({
    List<ShopMemberProfile>? members,
    List<PendingRequestProfile>? pendingRequests,
    ShopInvite? activeInvite,
    bool clearActiveInvite = false,
    String? actionError,
    bool clearActionError = false,
    bool? isProcessingAction,
  }) {
    return ShopMembersState(
      members: members ?? this.members,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      activeInvite: clearActiveInvite ? null : activeInvite ?? this.activeInvite,
      actionError: clearActionError ? null : actionError ?? this.actionError,
      isProcessingAction: isProcessingAction ?? this.isProcessingAction,
    );
  }
}

class ShopMembersController extends AsyncNotifier<ShopMembersState> {
  @override
  Future<ShopMembersState> build() async {
    final session = await ref.watch(shopSessionControllerProvider.future);
    final activeShop = session.activeShop;
    if (activeShop == null) {
      throw StateError('No active shop');
    }

    final repo = ref.watch(shopRepositoryProvider);
    final isOwner = activeShop.membership.role == ShopMembershipRole.owner;

    if (!isOwner) {
      final user = await ref.watch(authUserProvider.future);
      final email = user?.email ?? 'Me';
      return ShopMembersState(
        members: [
          ShopMemberProfile(
            userId: activeShop.membership.userId,
            email: email,
            role: activeShop.membership.role,
            createdAt: activeShop.membership.createdAt,
          ),
        ],
      );
    }

    final results = await Future.wait([
      repo.listMembersWithProfiles(activeShop.shop.id),
      repo.listPendingRequestsWithProfiles(activeShop.shop.id),
      repo.getActiveInvite(activeShop.shop.id),
    ]);

    return ShopMembersState(
      members: results[0] as List<ShopMemberProfile>,
      pendingRequests: results[1] as List<PendingRequestProfile>,
      activeInvite: results[2] as ShopInvite?,
    );
  }

  Future<void> reviewRequest(String requestId, JoinRequestStatus status) async {
    final current = state.requireValue;
    if (current.isProcessingAction) return;

    state = AsyncData(current.copyWith(isProcessingAction: true, clearActionError: true));
    try {
      await ref.read(shopRepositoryProvider).reviewJoinRequest(requestId, status);
      // Reload everything
      ref.invalidateSelf();
    } on ShopAccessException catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isProcessingAction: false, actionError: error.message));
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(
          isProcessingAction: false,
          actionError: 'Could not update request status.',
        ),
      );
    }
  }

  Future<void> rotateInvite() async {
    final current = state.requireValue;
    if (current.isProcessingAction) return;

    final session = ref.read(shopSessionControllerProvider).requireValue;
    final shopId = session.activeShop!.shop.id;

    state = AsyncData(current.copyWith(isProcessingAction: true, clearActionError: true));
    try {
      final invite = await ref.read(shopRepositoryProvider).rotateInviteCode(shopId);
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isProcessingAction: false, activeInvite: invite));
    } on ShopAccessException catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isProcessingAction: false, actionError: error.message));
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isProcessingAction: false, actionError: 'Could not rotate invite code.'),
      );
    }
  }

  Future<void> toggleInviteStatus(bool isActive) async {
    final current = state.requireValue;
    if (current.isProcessingAction) return;

    final session = ref.read(shopSessionControllerProvider).requireValue;
    final shopId = session.activeShop!.shop.id;

    state = AsyncData(current.copyWith(isProcessingAction: true, clearActionError: true));
    try {
      await ref.read(shopRepositoryProvider).updateInviteStatus(shopId, isActive);
      // We can just invalidate to reload the exact state
      ref.invalidateSelf();
    } on ShopAccessException catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isProcessingAction: false, actionError: error.message));
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isProcessingAction: false, actionError: 'Could not update invite status.'),
      );
    }
  }
}
