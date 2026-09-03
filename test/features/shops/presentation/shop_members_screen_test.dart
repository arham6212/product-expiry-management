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
import 'package:product_expiry_management/features/shops/presentation/shop_members_screen.dart';

void main() {
  testWidgets('active invite is rendered and rotating updates the QR payload', (tester) async {
    final createdAt = DateTime.utc(2026, 8, 30);
    final repository = InMemoryShopRepository(
      userId: 'owner-1',
      shops: [_ownerAccess(createdAt)],
      invites: [
        ShopInvite(
          id: 'invite-1',
          shopId: 'shop-1',
          code: 'OLD123',
          isActive: true,
          createdAt: createdAt,
          createdBy: 'owner-1',
          expiresAt: DateTime.utc(2030),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            InMemoryAuthService(
              currentUser: AuthenticatedUser(id: 'owner-1', email: 'owner@example.test'),
            ),
          ),
          shopRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ShopMembersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shop-invite:OLD123')), findsOneWidget);

    await tester.tap(find.text('Generate New Code'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shop-invite:I00002')), findsOneWidget);
    expect((await repository.getActiveInvite('shop-1'))?.code, 'I00002');
  });
}

ShopAccess _ownerAccess(DateTime createdAt) {
  return ShopAccess(
    shop: Shop(
      id: 'shop-1',
      name: 'Test Shop',
      timeZone: 'UTC',
      currencyCode: 'USD',
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    membership: ShopMembership(
      shopId: 'shop-1',
      userId: 'owner-1',
      role: ShopMembershipRole.owner,
      createdAt: createdAt,
    ),
  );
}
