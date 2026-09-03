import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_dependencies.dart';
import 'package:product_expiry_management/app/expiry_management_app.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';

void main() {
  final environment = AppEnvironment.parse(
    flavor: 'production',
    supabaseUrl: 'https://project.supabase.co',
    supabasePublishableKey: 'sb_publishable_test-key',
  );

  testWidgets('shows the action-oriented home dashboard', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo Shop'), findsOneWidget);
    expect(find.text('items need attention'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Value at risk'), findsOneWidget);
  });

  testWidgets('navigates to the inventory placeholder', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Receive stock'), findsNWidgets(2));
    expect(find.byKey(const Key('openReceiveStockButton')), findsOneWidget);
  });

  testWidgets('continues from resolved Product into shop-owned receiving', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeInput')), '6281007000066');
    await tester.tap(find.byKey(const Key('resolveBarcodeButton')));
    await tester.pumpAndSettle();
    expect(find.text('Almarai Milk 1L'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continueWithProductButton')));
    await tester.pumpAndSettle();

    expect(find.text('Receive product stock'), findsOneWidget);
    final productField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('productField')),
    );
    expect(productField.initialValue, 'product-almarai-milk-1l');
  });
}
