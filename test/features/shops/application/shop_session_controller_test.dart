import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/features/auth/application/auth_controller.dart';
import 'package:product_expiry_management/features/auth/application/auth_service.dart';
import 'package:product_expiry_management/features/auth/data/in_memory_auth_service.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';
import 'package:product_expiry_management/features/shops/data/in_memory_shop_repository.dart';

void main() {
  const user = AuthenticatedUser(id: 'user-1', email: 'owner@example.test');

  testWidgets('clears the active shop when authentication ends', (tester) async {
    final auth = InMemoryAuthService(currentUser: user);
    await _pumpSession(
      tester,
      auth: auth,
      repository: InMemoryShopRepository(userId: user.id, shops: [_access('shop-1')]),
    );

    expect(find.text('shop-1'), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.text('signed-out'), findsOneWidget);
  });

  testWidgets('same-user auth refresh does not reload or clear the shop', (tester) async {
    final auth = _MutableAuthService(user);
    final repository = _CountingShopRepository(
      InMemoryShopRepository(userId: user.id, shops: [_access('shop-1')]),
    );
    await _pumpSession(tester, auth: auth, repository: repository);

    expect(find.text('shop-1'), findsOneWidget);
    expect(repository.listCalls, 1);

    auth.emit(const AuthenticatedUser(id: 'user-1', email: 'new@example.test'));
    await tester.pumpAndSettle();

    expect(find.text('shop-1'), findsOneWidget);
    expect(repository.listCalls, 1);
    await auth.close();
  });
}

Future<void> _pumpSession(
  WidgetTester tester, {
  required AuthService auth,
  required ShopRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        shopRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: Scaffold(body: _SessionProbe())),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MutableAuthService implements AuthService {
  _MutableAuthService(this._currentUser);

  AuthenticatedUser? _currentUser;
  final _changes = StreamController<AuthenticatedUser?>.broadcast();

  @override
  AuthenticatedUser? get currentUser => _currentUser;

  @override
  Stream<AuthenticatedUser?> get userChanges => _changes.stream;

  void emit(AuthenticatedUser? user) {
    _currentUser = user;
    _changes.add(user);
  }

  Future<void> close() => _changes.close();

  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<AuthSignUpResult> signUp({required String email, required String password}) async {
    return const AuthSignUpResult(requiresEmailConfirmation: false);
  }
}

final class _CountingShopRepository implements ShopRepository {
  _CountingShopRepository(this.delegate);

  final ShopRepository delegate;
  var listCalls = 0;

  @override
  Future<ShopAccess> createShopWithOwner(String name) {
    return delegate.createShopWithOwner(name);
  }

  @override
  @override
  Future<void> requestToJoinShop(String code) => delegate.requestToJoinShop(code);

  @override
  Future<List<ShopJoinRequest>> listPendingRequests(String shopId) =>
      delegate.listPendingRequests(shopId);

  @override
  Future<void> reviewJoinRequest(String requestId, JoinRequestStatus newStatus) =>
      delegate.reviewJoinRequest(requestId, newStatus);

  @override
  Future<ShopInvite?> getActiveInvite(String shopId) => delegate.getActiveInvite(shopId);

  @override
  Future<ShopInvite> rotateInviteCode(String shopId) => delegate.rotateInviteCode(shopId);

  @override
  Future<void> updateInviteStatus(String shopId, bool isActive) =>
      delegate.updateInviteStatus(shopId, isActive);

  @override
  Future<List<ShopMembership>> listMembers(String shopId) => delegate.listMembers(shopId);

  @override
  Future<ShopJoinRequest?> getMyPendingRequest() => delegate.getMyPendingRequest();

  @override
  Future<List<PendingRequestProfile>> listPendingRequestsWithProfiles(String shopId) =>
      delegate.listPendingRequestsWithProfiles(shopId);

  @override
  Future<List<ShopMemberProfile>> listMembersWithProfiles(String shopId) =>
      delegate.listMembersWithProfiles(shopId);

  @override
  Future<List<ShopAccess>> listForCurrentUser() {
    listCalls += 1;
    return delegate.listForCurrentUser();
  }
}

class _SessionProbe extends ConsumerWidget {
  const _SessionProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    if (user case AsyncData(value: null)) return const Text('signed-out');

    return switch (ref.watch(shopSessionControllerProvider)) {
      AsyncLoading() => const CircularProgressIndicator(),
      AsyncError() => const Text('error'),
      AsyncData(:final value) when value.isChoosingShop => Column(
        children: [
          const Text('choose'),
          TextButton(
            key: const Key('selectLastShop'),
            onPressed: () =>
                ref.read(shopSessionControllerProvider.notifier).selectShop(value.shops.last),
            child: const Text('select'),
          ),
        ],
      ),
      AsyncData(:final value) => Text(value.activeShop?.shop.id ?? 'none'),
    };
  }
}

ShopAccess _access(String id) {
  final now = DateTime.utc(2026, 8, 29);
  return ShopAccess(
    shop: Shop(
      id: id,
      name: id,
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: now,
      updatedAt: now,
    ),
    membership: ShopMembership(
      shopId: id,
      userId: 'user-1',
      role: ShopMembershipRole.owner,
      createdAt: now,
    ),
  );
}
