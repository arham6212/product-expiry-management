import '../../../domain/entities/domain_models.dart';
import '../../../domain/entities/shop_invite_qr.dart';
import '../application/shop_access.dart';

final class InMemoryShopRepository implements ShopRepository {
  InMemoryShopRepository({
    required this.userId,
    Iterable<ShopAccess> shops = const [],
    Iterable<ShopInvite> invites = const [],
  }) : _shops = List.of(shops),
       _invites = List.of(invites) {
    _inviteSequence = _invites.length;
  }

  final String userId;
  final List<ShopAccess> _shops;
  final List<ShopInvite> _invites;
  var _inviteSequence = 0;

  @override
  Future<List<ShopAccess>> listForCurrentUser() async => List.unmodifiable(_shops);

  @override
  Future<ShopAccess> createShopWithOwner(String name) async {
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedName.isEmpty) {
      throw const ShopAccessException('Enter a shop name.');
    }
    final now = DateTime.now().toUtc();
    final shop = Shop(
      id: 'shop-${_shops.length + 1}',
      name: normalizedName,
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: now,
      updatedAt: now,
    );
    final access = ShopAccess(
      shop: shop,
      membership: ShopMembership(
        shopId: shop.id,
        userId: userId,
        role: ShopMembershipRole.owner,
        createdAt: now,
      ),
    );
    _shops.add(access);
    return access;
  }

  final List<String> joinRequests = [];

  @override
  Future<void> requestToJoinShop(String code) async {
    joinRequests.add(code);
  }

  @override
  Future<List<ShopJoinRequest>> listPendingRequests(String shopId) async {
    return [];
  }

  @override
  Future<void> reviewJoinRequest(String requestId, JoinRequestStatus newStatus) async {
    throw UnimplementedError();
  }

  @override
  Future<ShopInvite?> getActiveInvite(String shopId) async {
    final now = DateTime.now().toUtc();
    final matches =
        _invites
            .where(
              (invite) => invite.shopId == shopId && invite.isActive && !invite.isExpiredAt(now),
            )
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return matches.firstOrNull;
  }

  @override
  Future<ShopInvite> rotateInviteCode(String shopId) async {
    for (var index = 0; index < _invites.length; index += 1) {
      final invite = _invites[index];
      if (invite.shopId == shopId && invite.isActive) {
        _invites[index] = invite.copyWith(isActive: false);
      }
    }
    final now = DateTime.now().toUtc();
    _inviteSequence += 1;
    final invite = ShopInvite(
      id: 'invite-$_inviteSequence',
      shopId: shopId,
      code: 'I${_inviteSequence.toString().padLeft(5, '0')}',
      isActive: true,
      createdAt: now,
      createdBy: userId,
      expiresAt: now.add(const Duration(days: 7)),
    );
    _invites.add(invite);
    return invite;
  }

  @override
  Future<void> updateInviteStatus(String shopId, bool isActive) async {
    if (!isActive) {
      for (var index = 0; index < _invites.length; index += 1) {
        final invite = _invites[index];
        if (invite.shopId == shopId && invite.isActive) {
          _invites[index] = invite.copyWith(isActive: false);
        }
      }
      return;
    }

    final now = DateTime.now().toUtc();
    final candidates =
        _invites
            .where(
              (invite) =>
                  invite.shopId == shopId &&
                  !invite.isExpiredAt(now) &&
                  ShopInviteQr.isValidCode(invite.code),
            )
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    if (candidates.isEmpty) {
      await rotateInviteCode(shopId);
      return;
    }

    final selectedId = candidates.first.id;
    for (var index = 0; index < _invites.length; index += 1) {
      final invite = _invites[index];
      if (invite.shopId == shopId) {
        _invites[index] = invite.copyWith(isActive: invite.id == selectedId);
      }
    }
  }

  @override
  Future<List<ShopMembership>> listMembers(String shopId) async {
    return [];
  }

  @override
  Future<ShopJoinRequest?> getMyPendingRequest() async {
    return null;
  }

  @override
  Future<List<PendingRequestProfile>> listPendingRequestsWithProfiles(String shopId) async {
    return [];
  }

  @override
  Future<List<ShopMemberProfile>> listMembersWithProfiles(String shopId) async {
    return _shops
        .where((access) => access.shop.id == shopId)
        .map(
          (access) => ShopMemberProfile(
            userId: access.membership.userId,
            email: access.membership.userId,
            role: access.membership.role,
            createdAt: access.membership.createdAt,
          ),
        )
        .toList();
  }
}
