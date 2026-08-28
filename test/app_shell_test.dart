import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/app/expiry_management_app.dart';
import 'package:product_expiry_management/core/config/app_environment.dart';

void main() {
  const environment = AppEnvironment(flavor: AppFlavor.production, apiBaseUrl: null);

  testWidgets('shows the action-oriented home placeholder', (tester) async {
    await tester.pumpWidget(const ExpiryManagementApp(environment: environment));

    expect(find.text('What needs attention today?'), findsOneWidget);
    expect(find.text('Your action queue is ready'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
  });

  testWidgets('navigates to the inventory placeholder', (tester) async {
    await tester.pumpWidget(const ExpiryManagementApp(environment: environment));

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Products and batches will appear here after the core inventory slice is implemented.',
      ),
      findsOneWidget,
    );
  });
}
