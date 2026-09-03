import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_dependencies.dart';
import 'package:product_expiry_management/app/expiry_management_app.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';

void main() {
  testWidgets('owner reaches storefront management and can disable publication', (tester) async {
    final environment = AppEnvironment.parse(
      flavor: 'development',
      supabaseUrl: 'https://project.supabase.co',
      supabasePublishableKey: 'sb_publishable_test-key',
      enableStorefront: 'true',
    );
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openShopOperationsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageStorefrontTile')));
    await tester.pumpAndSettle();

    expect(find.text('Public Storefront'), findsWidgets);
    expect(find.text('Almarai Milk 1L'), findsOneWidget);
    final toggle = find.byKey(const Key('storefrontEnabledSwitch'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Only owners and managers can see this draft.'), findsOneWidget);
    expect(find.byKey(const Key('createDeal-product-almarai-milk-1l')), findsOneWidget);
  });
}
