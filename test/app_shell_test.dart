import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/app_dependencies.dart';
import 'package:product_expiry_management/app/expiry_management_app.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';
import 'package:product_expiry_management/features/inventory/presentation/product_details_page.dart';

void main() {
  final environment = AppEnvironment.parse(
    flavor: 'production',
    supabaseUrl: 'https://project.supabase.co',
    supabasePublishableKey: 'sb_publishable_test-key',
  );

  testWidgets('shows the real expiry dashboard', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo Shop'), findsOneWidget);
    expect(find.byKey(const Key('scanProductHomeButton')), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Almarai Milk 1L'), findsOneWidget);
    expect(find.text('Value at risk'), findsNothing);
  });

  testWidgets('navigates to the inventory placeholder', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Receive stock'), findsNWidgets(2));
    expect(find.byKey(const Key('openReceiveStockButton')), findsOneWidget);
  });

  testWidgets('barcode-less creation is secondary on scanner and hands off to receiving', (
    tester,
  ) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsNothing);
    await tester.tap(find.byKey(const Key('scanProductHomeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scannerWithoutBarcodeButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeLessProductName')), 'Loose apples');
    await tester.tap(find.byKey(const Key('saveBarcodeLessProductButton')));
    await tester.pumpAndSettle();
    expect(find.text('Loose apples'), findsOneWidget);
    expect(find.text('Save stock'), findsOneWidget);
    expect(find.byKey(const Key('addProductWithoutBarcodeButton')), findsNothing);
  });

  testWidgets('continues from resolved Product into shop-owned receiving', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scanProductHomeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can’t scan? Enter barcode manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeInput')), '6281007000062');
    await tester.tap(find.byKey(const Key('resolveBarcodeButton')));
    await tester.pumpAndSettle();
    expect(find.text('Almarai Milk 1L'), findsOneWidget);

    expect(find.byKey(const Key('saveReceivedStockButton')), findsOneWidget);
    final productField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('productField')),
    );
    expect(productField.initialValue, 'product-almarai-milk-1l');

    await tester.enterText(find.byKey(const Key('sellingPriceField')), '7.50');
    await tester.enterText(find.byKey(const Key('expiryField')), '2027-01-15');
    await tester.enterText(find.byKey(const Key('quantityField')), '12');
    await tester.ensureVisible(find.byKey(const Key('saveReceivedStockButton')));
    await tester.tap(find.byKey(const Key('saveReceivedStockButton')));
    await tester.pumpAndSettle();
    expect(find.text('Stock received'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('scanNextProductButton')));
    await tester.tap(find.byKey(const Key('scanNextProductButton')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Stock received'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scanNextProductButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can’t scan? Enter barcode manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcodeInput')), '6281007000062');
    await tester.tap(find.byKey(const Key('resolveBarcodeButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saveReceivedStockButton')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('quantityField'))).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('expiryField'))).controller!.text,
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scanProductHomeButton')), findsOneWidget);
    expect(find.byKey(const Key('barcodeInput')), findsNothing);
  });

  testWidgets('Alerts opens the affected product details', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Almarai Milk 1L'), findsOneWidget);
    expect(find.text('2 days left'), findsOneWidget);

    await tester.tap(find.text('Almarai Milk 1L'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailsPage), findsOneWidget);
    expect(find.text('Active batches'), findsOneWidget);
  });

  testWidgets('Home urgent row opens product details', (tester) async {
    await tester.pumpWidget(
      ExpiryManagementApp(environment: environment, dependencies: AppDependencies.inMemory()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Almarai Milk 1L'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailsPage), findsOneWidget);
    expect(find.text('Active batches'), findsOneWidget);
  });
}
