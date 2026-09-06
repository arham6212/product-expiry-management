import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/expiry_risk_service.dart';
import '../../../domain/value_objects/local_date.dart';
import '../../shops/application/shop_access.dart';
import '../../shops/application/shop_session_controller.dart';
import 'expiry_dashboard.dart';
import 'inventory_repository_provider.dart';

final _expiryDashboardForShopProvider = AsyncNotifierProvider.autoDispose
    .family<ExpiryDashboardController, ExpiryDashboardState, String>(
      ExpiryDashboardController.new,
      retry: (retryCount, error) => null,
    );

final expiryDashboardProvider = Provider.autoDispose<AsyncValue<ExpiryDashboardState>>((ref) {
  final activeShop = ref.watch(activeShopProvider);
  if (activeShop == null) {
    return AsyncError(
      const ShopAccessException('Select a shop before loading its expiry dashboard.'),
      StackTrace.current,
    );
  }
  return ref.watch(_expiryDashboardForShopProvider(activeShop.shop.id));
});

final expiryDashboardActionsProvider = Provider.autoDispose<ExpiryDashboardActions>(
  ExpiryDashboardActions.new,
);

final class ExpiryDashboardState {
  const ExpiryDashboardState._({
    required this.shopId,
    required this.referenceDate,
    required this.items,
    required this.expired,
    required this.expiresToday,
    required this.next7Days,
    required this.days8To30,
    required this.later,
    required this.needsDate,
  });

  factory ExpiryDashboardState.fromSnapshot({
    required String shopId,
    required ExpiryDashboardSnapshot snapshot,
  }) {
    final items = List<ExpiryDashboardItem>.unmodifiable(snapshot.items);
    return ExpiryDashboardState._(
      shopId: shopId,
      referenceDate: snapshot.referenceDate,
      items: items,
      expired: _itemsFor(items, ExpiryRiskCategory.expired),
      expiresToday: _itemsFor(items, ExpiryRiskCategory.expiresToday),
      next7Days: _itemsFor(items, ExpiryRiskCategory.next7Days),
      days8To30: _itemsFor(items, ExpiryRiskCategory.days8To30),
      later: _itemsFor(items, ExpiryRiskCategory.later),
      needsDate: List.unmodifiable(items.where((item) => item.riskCategory == null)),
    );
  }

  final String shopId;
  final LocalDate referenceDate;
  final List<ExpiryDashboardItem> items;
  final List<ExpiryDashboardItem> expired;
  final List<ExpiryDashboardItem> expiresToday;
  final List<ExpiryDashboardItem> next7Days;
  final List<ExpiryDashboardItem> days8To30;
  final List<ExpiryDashboardItem> later;
  final List<ExpiryDashboardItem> needsDate;
}

final class ExpiryDashboardController extends AsyncNotifier<ExpiryDashboardState> {
  ExpiryDashboardController(this.shopId);

  final String shopId;

  @override
  Future<ExpiryDashboardState> build() async {
    final activeShop = ref.watch(activeShopProvider);
    if (activeShop == null || activeShop.shop.id != shopId) {
      throw const ShopAccessException('Select a shop before loading its expiry dashboard.');
    }

    final snapshot = await ref
        .watch(inventoryRepositoryProvider)
        .loadExpiryDashboard(shopId: shopId);

    if (ref.read(activeShopProvider)?.shop.id != shopId) {
      throw const ShopAccessException(
        'The active shop changed while the expiry dashboard was loading.',
      );
    }

    return ExpiryDashboardState.fromSnapshot(shopId: shopId, snapshot: snapshot);
  }
}

final class ExpiryDashboardActions {
  ExpiryDashboardActions(this._ref);

  final Ref _ref;

  Future<ExpiryDashboardState> get future {
    final shopId = _activeShopId();
    if (shopId == null) {
      return Future.error(
        const ShopAccessException('Select a shop before loading its expiry dashboard.'),
      );
    }
    return _ref.read(_expiryDashboardForShopProvider(shopId).future);
  }

  Future<void> refresh() async {
    final shopId = _activeShopId();
    if (shopId == null) return;
    _ref.invalidate(_expiryDashboardForShopProvider(shopId));
    await _ref.read(_expiryDashboardForShopProvider(shopId).future);
  }

  Future<void> retry() => refresh();

  void invalidateCurrent() {
    final shopId = _activeShopId();
    if (shopId != null) {
      _ref.invalidate(_expiryDashboardForShopProvider(shopId));
    }
  }

  String? _activeShopId() => _ref.read(activeShopProvider)?.shop.id;
}

List<ExpiryDashboardItem> _itemsFor(
  Iterable<ExpiryDashboardItem> items,
  ExpiryRiskCategory category,
) {
  return List.unmodifiable(items.where((item) => item.riskCategory == category));
}
