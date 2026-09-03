import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/domain_models.dart';
import 'package:product_expiry_management/features/auth/application/auth_controller.dart';
import 'package:product_expiry_management/features/auth/application/auth_service.dart';
import 'package:product_expiry_management/features/auth/data/in_memory_auth_service.dart';
import 'package:product_expiry_management/features/auth/presentation/authenticated_shop_gate.dart';
import 'package:product_expiry_management/features/shops/application/shop_access.dart';
import 'package:product_expiry_management/features/shops/application/shop_session_controller.dart';
import 'package:product_expiry_management/features/shops/data/in_memory_shop_repository.dart';

void main() {
  const user = AuthenticatedUser(id: 'user-1', email: 'owner@example.test');

  Future<void> pumpGate(
    WidgetTester tester, {
    required InMemoryAuthService auth,
    required InMemoryShopRepository shops,
    ValueChanged<ShopAccess>? onActive,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          shopRepositoryProvider.overrideWithValue(shops),
        ],
        child: MaterialApp(
          home: AuthenticatedShopGate(
            enableStorefront: false,
            builder: (_, access, selectAnother) {
              onActive?.call(access);
              return Scaffold(body: Text('Active: ${access.shop.name}'));
            },
          ),
        ),
      ),
    );
  }

  testWidgets('signed-out users see email/password authentication', (tester) async {
    final auth = InMemoryAuthService();
    await pumpGate(
      tester,
      auth: auth,
      shops: InMemoryShopRepository(userId: user.id),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in for shop operations'), findsOneWidget);
    expect(find.byKey(const Key('authEmailField')), findsOneWidget);
    expect(find.byKey(const Key('authPasswordField')), findsOneWidget);
  });

  testWidgets('one membership is selected automatically', (tester) async {
    ShopAccess? active;
    await pumpGate(
      tester,
      auth: InMemoryAuthService(currentUser: user),
      shops: InMemoryShopRepository(userId: user.id, shops: [_access('shop-1', 'Only Shop')]),
      onActive: (value) => active = value,
    );
    await tester.pumpAndSettle();

    expect(find.text('Active: Only Shop'), findsOneWidget);
    expect(active?.shop.id, 'shop-1');
  });

  testWidgets('user without memberships can create a first shop', (tester) async {
    ShopAccess? active;
    await pumpGate(
      tester,
      auth: InMemoryAuthService(currentUser: user),
      shops: InMemoryShopRepository(userId: user.id),
      onActive: (value) => active = value,
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a new shop'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('createShopNameField')), 'Corner Market');
    await tester.tap(find.byKey(const Key('createShopButton')));
    await tester.pumpAndSettle();

    expect(find.text('Active: Corner Market'), findsOneWidget);
    expect(active?.membership.role, ShopMembershipRole.owner);
  });

  testWidgets('manual code entry joins shop', (tester) async {
    final shops = InMemoryShopRepository(userId: user.id);
    await pumpGate(
      tester,
      auth: InMemoryAuthService(currentUser: user),
      shops: shops,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('joinShopCodeField')), 'A1B2C3');
    await tester.tap(find.byKey(const Key('joinShopButton')));
    await tester.pumpAndSettle();

    expect(shops.joinRequests, contains('A1B2C3'));
  });
}

ShopAccess _access(String id, String name) {
  final now = DateTime.utc(2026, 8, 29);
  return ShopAccess(
    shop: Shop(
      id: id,
      name: name,
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
