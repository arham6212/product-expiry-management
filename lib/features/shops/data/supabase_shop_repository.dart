import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/domain_models.dart';
import '../application/shop_access.dart';

final class SupabaseShopRepository implements ShopRepository {
  const SupabaseShopRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ShopAccess>> listForCurrentUser() async {
    try {
      final rows = await _client
          .from('shop_memberships')
          .select(
            'shop_id,user_id,role,created_at,'
            'shops!inner(id,name,time_zone,currency_code,created_at,updated_at)',
          )
          .order('created_at');
      return List.unmodifiable(rows.map(_mapAccess));
    } on PostgrestException catch (error) {
      throw ShopAccessException('Shops could not be loaded.', cause: error);
    }
  }

  @override
  Future<ShopAccess> createShopWithOwner(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const ShopAccessException('Sign in before creating a shop.');
    }
    try {
      final response = await _client.rpc<Object?>(
        'create_shop_with_owner',
        params: {'shop_name': name.trim()},
      );
      final shop = _mapShop(_asMap(response));
      return ShopAccess(
        shop: shop,
        membership: ShopMembership(
          shopId: shop.id,
          userId: user.id,
          role: ShopMembershipRole.owner,
          createdAt: shop.createdAt,
        ),
      );
    } on PostgrestException catch (error) {
      throw ShopAccessException('The shop could not be created.', cause: error);
    }
  }

  @override
  Future<void> requestToJoinShop(String code) async {
    try {
      await _client.rpc<void>('request_to_join_shop', params: {'join_code': code.trim()});
    } on PostgrestException catch (error) {
      throw ShopAccessException(error.message, cause: error);
    }
  }

  @override
  Future<List<ShopJoinRequest>> listPendingRequests(String shopId) async {
    try {
      final rows = await _client
          .from('shop_join_requests')
          .select('*')
          .eq('shop_id', shopId)
          .eq('status', 'pending')
          .order('created_at');
      return rows.map(_mapJoinRequest).toList();
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load join requests.', cause: error);
    }
  }

  @override
  Future<void> reviewJoinRequest(String requestId, JoinRequestStatus newStatus) async {
    try {
      await _client.rpc<void>(
        'review_join_request',
        params: {'request_id': requestId, 'new_status': newStatus.name},
      );
    } on PostgrestException catch (error) {
      throw ShopAccessException(error.message, cause: error);
    }
  }

  @override
  Future<ShopInvite?> getActiveInvite(String shopId) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'get_active_shop_invite',
        params: {'target_shop_id': shopId},
      );
      if (rows.isEmpty) return null;
      return _mapShopInvite(_asMap(rows.single));
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load invite code.', cause: error);
    }
  }

  @override
  Future<ShopInvite> rotateInviteCode(String shopId) async {
    try {
      final code = await _client.rpc<String>(
        'rotate_shop_invite_code',
        params: {'target_shop_id': shopId},
      );
      final rows = await _client
          .from('shop_invites')
          .select('*')
          .eq('shop_id', shopId)
          .eq('code', code)
          .limit(1);
      return _mapShopInvite(rows.single);
    } on PostgrestException catch (error) {
      throw ShopAccessException(error.message, cause: error);
    }
  }

  @override
  Future<void> updateInviteStatus(String shopId, bool isActive) async {
    try {
      await _client.rpc<void>(
        'update_shop_invite_status',
        params: {'target_shop_id': shopId, 'target_is_active': isActive},
      );
    } on PostgrestException catch (error) {
      throw ShopAccessException(error.message, cause: error);
    }
  }

  @override
  Future<List<ShopMembership>> listMembers(String shopId) async {
    try {
      final rows = await _client
          .from('shop_memberships')
          .select('*')
          .eq('shop_id', shopId)
          .order('created_at');
      return rows
          .map(
            (row) => ShopMembership(
              shopId: _requiredString(row, 'shop_id'),
              userId: _requiredString(row, 'user_id'),
              role: _mapRole(_requiredString(row, 'role')),
              createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load members.', cause: error);
    }
  }

  @override
  Future<ShopJoinRequest?> getMyPendingRequest() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final rows = await _client
          .from('shop_join_requests')
          .select('*')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .limit(1);
      if (rows.isEmpty) return null;
      return _mapJoinRequest(rows.single);
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load pending request.', cause: error);
    }
  }

  @override
  Future<List<PendingRequestProfile>> listPendingRequestsWithProfiles(String shopId) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'get_shop_pending_requests_with_users',
        params: {'target_shop_id': shopId},
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(
            (row) => PendingRequestProfile(
              requestId: _requiredString(row, 'request_id'),
              userId: _requiredString(row, 'user_id'),
              email: row['email']?.toString() ?? 'Unknown User',
              createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load requests.', cause: error);
    } catch (e) {
      throw ShopAccessException('Unexpected error loading requests.', cause: e);
    }
  }

  @override
  Future<List<ShopMemberProfile>> listMembersWithProfiles(String shopId) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'get_shop_members_with_users',
        params: {'target_shop_id': shopId},
      );
      return rows
          .cast<Map<String, dynamic>>()
          .map(
            (row) => ShopMemberProfile(
              userId: _requiredString(row, 'user_id'),
              email: row['email']?.toString() ?? 'Unknown User',
              role: _mapRole(_requiredString(row, 'role')),
              createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ShopAccessException('Could not load members.', cause: error);
    } catch (e) {
      throw ShopAccessException('Unexpected error loading members.', cause: e);
    }
  }
}

ShopAccess _mapAccess(Map<String, dynamic> row) {
  final shop = _mapShop(_asMap(row['shops']));
  return ShopAccess(
    shop: shop,
    membership: ShopMembership(
      shopId: _requiredString(row, 'shop_id'),
      userId: _requiredString(row, 'user_id'),
      role: _mapRole(_requiredString(row, 'role')),
      createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
    ),
  );
}

ShopMembershipRole _mapRole(String role) {
  return switch (role) {
    'owner' => ShopMembershipRole.owner,
    'manager' => ShopMembershipRole.manager,
    'worker' => ShopMembershipRole.worker,
    _ => throw const FormatException('Unknown shop membership role.'),
  };
}

Shop _mapShop(Map<String, dynamic> row) {
  return Shop(
    id: _requiredString(row, 'id'),
    name: _requiredString(row, 'name'),
    timeZone: _requiredString(row, 'time_zone'),
    currencyCode: _requiredString(row, 'currency_code'),
    createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
    updatedAt: DateTime.parse(_requiredString(row, 'updated_at')).toUtc(),
  );
}

ShopJoinRequest _mapJoinRequest(Map<String, dynamic> row) {
  return ShopJoinRequest(
    id: _requiredString(row, 'id'),
    shopId: _requiredString(row, 'shop_id'),
    userId: _requiredString(row, 'user_id'),
    status: switch (_requiredString(row, 'status')) {
      'pending' => JoinRequestStatus.pending,
      'approved' => JoinRequestStatus.approved,
      'rejected' => JoinRequestStatus.rejected,
      _ => throw const FormatException('Unknown request status.'),
    },
    createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
    reviewedAt: row['reviewed_at'] != null
        ? DateTime.parse(row['reviewed_at'] as String).toUtc()
        : null,
    reviewedBy: row['reviewed_by'] as String?,
  );
}

ShopInvite _mapShopInvite(Map<String, dynamic> row) {
  return ShopInvite(
    id: _requiredString(row, 'id'),
    shopId: _requiredString(row, 'shop_id'),
    code: _requiredString(row, 'code'),
    isActive: row['is_active'] as bool,
    createdAt: DateTime.parse(_requiredString(row, 'created_at')).toUtc(),
    createdBy: _requiredString(row, 'created_by'),
    expiresAt: DateTime.parse(_requiredString(row, 'expires_at')).toUtc(),
  );
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is List<Object?> && value.length == 1 && value.single is Map<String, dynamic>) {
    return value.single! as Map<String, dynamic>;
  }
  throw const FormatException('Expected one shop record.');
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key.');
  return value;
}
