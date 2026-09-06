import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'receive_stock.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  throw StateError('inventoryRepositoryProvider must be overridden at the application root.');
});
