import '../../../domain/entities/domain_models.dart';

final class ShopAccess {
  const ShopAccess({required this.shop, required this.membership});

  final Shop shop;
  final ShopMembership membership;
}

final class ShopAccessException implements Exception {
  const ShopAccessException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ShopAccessException: $message';
}

abstract interface class ShopRepository {
  Future<List<ShopAccess>> listForCurrentUser();

  Future<ShopAccess> createShopWithOwner(String name);

  Future<void> requestToJoinShop(String code);

  Future<List<ShopJoinRequest>> listPendingRequests(String shopId);

  Future<void> reviewJoinRequest(String requestId, JoinRequestStatus newStatus);

  Future<ShopInvite?> getActiveInvite(String shopId);

  Future<ShopInvite> rotateInviteCode(String shopId);

  Future<void> updateInviteStatus(String shopId, bool isActive);

  Future<List<ShopMembership>> listMembers(String shopId);

  Future<List<PendingRequestProfile>> listPendingRequestsWithProfiles(String shopId);

  Future<List<ShopMemberProfile>> listMembersWithProfiles(String shopId);

  Future<ShopJoinRequest?> getMyPendingRequest();
}
