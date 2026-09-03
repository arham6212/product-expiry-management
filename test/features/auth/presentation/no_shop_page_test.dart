import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/features/auth/application/auth_controller.dart';
import 'package:product_expiry_management/features/auth/application/auth_service.dart';
import 'package:product_expiry_management/features/auth/data/in_memory_auth_service.dart';
import 'package:product_expiry_management/features/auth/presentation/no_shop_page.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';
import 'package:product_expiry_management/features/shops/data/in_memory_shop_repository.dart';

void main() {
  const worker = AuthenticatedUser(id: 'worker-1', email: 'worker@example.test');

  testWidgets('manual code still uses the shop session join operation', (tester) async {
    final repository = InMemoryShopRepository(userId: worker.id);
    await _pumpNoShopPage(tester, repository: repository);

    await tester.enterText(find.byKey(const Key('joinShopCodeField')), ' ab12cd ');
    await tester.tap(find.byKey(const Key('joinShopButton')));
    await tester.pump();

    expect(repository.joinRequests, ['AB12CD']);
  });

  testWidgets('scan selects a code and requires confirmation through the same join operation', (
    tester,
  ) async {
    final repository = InMemoryShopRepository(userId: worker.id);
    await _pumpNoShopPage(tester, repository: repository, scanInviteCode: (_) async => 'A1B2C3');

    await tester.tap(find.byTooltip('Scan QR Code'));
    await tester.pumpAndSettle();

    expect(repository.joinRequests, isEmpty);
    expect(find.byKey(const Key('scannedInviteConfirmation')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('scannedInviteConfirmation')),
        matching: find.textContaining('A1B2C3'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('joinShopCodeField'))).controller?.text,
      'A1B2C3',
    );

    await tester.tap(find.byKey(const Key('joinShopButton')));
    await tester.pump();

    expect(repository.joinRequests, ['A1B2C3']);
  });

  testWidgets('invalid or revoked invite failure remains visible for retry', (tester) async {
    final repository = _RejectingShopRepository(InMemoryShopRepository(userId: worker.id));
    await _pumpNoShopPage(tester, repository: repository);

    await tester.enterText(find.byKey(const Key('joinShopCodeField')), 'BAD123');
    await tester.tap(find.byKey(const Key('joinShopButton')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid, expired, or revoked invite code.'), findsOneWidget);
    expect(find.byKey(const Key('joinShopButton')), findsOneWidget);
  });
}

Future<void> _pumpNoShopPage(
  WidgetTester tester, {
  required ShopRepository repository,
  InviteCodeScanner? scanInviteCode,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(
          InMemoryAuthService(
            currentUser: AuthenticatedUser(id: 'worker-1', email: 'worker@example.test'),
          ),
        ),
        shopRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: _NoShopHarness(scanInviteCode: scanInviteCode)),
    ),
  );
  await tester.pumpAndSettle();
}

class _NoShopHarness extends ConsumerWidget {
  const _NoShopHarness({this.scanInviteCode});

  final InviteCodeScanner? scanInviteCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(shopSessionControllerProvider)) {
      AsyncData(:final value) => NoShopPage(session: value, scanInviteCode: scanInviteCode),
      AsyncError() => const Text('error'),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

final class _RejectingShopRepository implements ShopRepository {
  _RejectingShopRepository(this._delegate);

  final ShopRepository _delegate;

  @override
  Future<void> requestToJoinShop(String code) {
    throw const ShopAccessException('Invalid, expired, or revoked invite code.');
  }

  @override
  Future<ShopAccess> createShopWithOwner(String name) => _delegate.createShopWithOwner(name);

  @override
  Future<ShopInvite?> getActiveInvite(String shopId) => _delegate.getActiveInvite(shopId);

  @override
  Future<ShopJoinRequest?> getMyPendingRequest() => _delegate.getMyPendingRequest();

  @override
  Future<List<ShopAccess>> listForCurrentUser() => _delegate.listForCurrentUser();

  @override
  Future<List<ShopMemberProfile>> listMembersWithProfiles(String shopId) =>
      _delegate.listMembersWithProfiles(shopId);

  @override
  Future<List<ShopMembership>> listMembers(String shopId) => _delegate.listMembers(shopId);

  @override
  Future<List<ShopJoinRequest>> listPendingRequests(String shopId) =>
      _delegate.listPendingRequests(shopId);

  @override
  Future<List<PendingRequestProfile>> listPendingRequestsWithProfiles(String shopId) =>
      _delegate.listPendingRequestsWithProfiles(shopId);

  @override
  Future<void> reviewJoinRequest(String requestId, JoinRequestStatus newStatus) =>
      _delegate.reviewJoinRequest(requestId, newStatus);

  @override
  Future<ShopInvite> rotateInviteCode(String shopId) => _delegate.rotateInviteCode(shopId);

  @override
  Future<void> updateInviteStatus(String shopId, bool isActive) =>
      _delegate.updateInviteStatus(shopId, isActive);
}
