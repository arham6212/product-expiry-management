import '../../../core/identity/local_id_generator.dart';
import '../../../domain/entities/domain_models.dart';
import '../../../domain/services/expiry_risk_service.dart';
import '../../../domain/value_objects/local_date.dart';
import '../application/expiry_dashboard.dart';
import '../application/receive_stock.dart';

enum ReceivingTransactionStage { batchStaged, movementStaged }

typedef TransactionStageObserver = void Function(ReceivingTransactionStage stage);
typedef EntityIdGenerator = String Function(String prefix);
typedef UtcClock = DateTime Function();

final class InMemoryInventoryRepository implements InventoryRepository {
  InMemoryInventoryRepository({
    Iterable<Product> products = const [],
    Iterable<Batch> batches = const [],
    Iterable<InventoryMovement> movements = const [],
    TransactionStageObserver? onTransactionStage,
    EntityIdGenerator? idGenerator,
    UtcClock? clock,
    LocalDate? expiryDashboardReferenceDate,
    ExpiryRiskService expiryRiskService = const CalendarExpiryRiskService(),
  }) : _products = {for (final product in products) product.id: product},
       _batches = List<Batch>.of(batches),
       _movements = List<InventoryMovement>.of(movements),
       _onTransactionStage = onTransactionStage,
       _idGenerator = idGenerator ?? LocalIdGenerator.next,
       _clock = clock ?? _systemUtcClock,
       _expiryDashboardReferenceDate = expiryDashboardReferenceDate ?? LocalDate(2000, 1, 1),
       _expiryRiskService = expiryRiskService;

  Map<String, Product> _products;
  List<Batch> _batches;
  List<InventoryMovement> _movements;
  Map<String, _StoredReceiving> _receivings = {};
  final TransactionStageObserver? _onTransactionStage;
  final EntityIdGenerator _idGenerator;
  final UtcClock _clock;
  final LocalDate _expiryDashboardReferenceDate;
  final ExpiryRiskService _expiryRiskService;

  List<Batch> get batches => List.unmodifiable(_batches);
  List<InventoryMovement> get movements => List.unmodifiable(_movements);

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    final products = _products.values.where((product) => product.shopId == shopId).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    return List.unmodifiable(products);
  }

  @override
  Future<ExpiryDashboardSnapshot> loadExpiryDashboard({required String shopId}) async {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.invalidInput,
        'A Shop ID is required to load the expiry dashboard.',
      );
    }

    final batches =
        _batches
            .where(
              (batch) =>
                  batch.shopId == normalizedShopId &&
                  (batch.currentQuantity == null || batch.currentQuantity! > 0),
            )
            .toList()
          ..sort(_compareDashboardBatches);
    final items = <ExpiryDashboardItem>[];

    for (final batch in batches) {
      final product = _products[batch.productId];
      if (product == null || product.shopId != normalizedShopId) {
        throw const InventoryRepositoryException(
          InventoryRepositoryFailureKind.invalidResponse,
          'Dashboard inventory references an unavailable Product.',
        );
      }
      final expiryDate = batch.expiryDate;
      items.add(
        ExpiryDashboardItem(
          shopId: batch.shopId,
          batchId: batch.id,
          productId: product.id,
          productName: product.name,
          productBrand: product.brand,
          expiryDate: expiryDate,
          daysToExpiry: expiryDate == null
              ? null
              : _expiryDashboardReferenceDate.daysUntil(expiryDate),
          riskCategory: expiryDate == null
              ? null
              : _expiryRiskService.classify(
                  expiryDate: expiryDate,
                  referenceDate: _expiryDashboardReferenceDate,
                ),
          currentQuantity: batch.currentQuantity,
          lotNumber: batch.lotCode,
          receivedAt: batch.createdAt,
        ),
      );
    }

    return ExpiryDashboardSnapshot(referenceDate: _expiryDashboardReferenceDate, items: items);
  }

  @override
  Future<ReceivingReceipt> receive(ReceivingRequest request) async {
    final receiptKey = '${request.shopId}:${request.idempotencyKey}';
    final prior = _receivings[receiptKey];
    if (prior != null) {
      if (!prior.request.hasSamePayload(request)) {
        throw const InventoryRepositoryException(
          InventoryRepositoryFailureKind.idempotencyConflict,
          'The idempotency key was already used with different receiving input.',
        );
      }
      return ReceivingReceipt(batch: prior.batch, movement: prior.movement, wasDuplicate: true);
    }

    final product = _products[request.productId];
    if (product == null || product.shopId != request.shopId) {
      throw const InventoryRepositoryException(
        InventoryRepositoryFailureKind.productUnavailable,
        'The Product is unavailable in the selected shop.',
      );
    }

    final now = _clock().toUtc();
    final batch = Batch(
      id: _idGenerator('batch'),
      shopId: request.shopId,
      productId: request.productId,
      expiryDate: request.expiryDate,
      currentQuantity: request.quantity,
      lotCode: request.lotNumber,
      createdAt: now,
      updatedAt: now,
    );
    final movement = InventoryMovement(
      id: _idGenerator('movement'),
      shopId: request.shopId,
      batchId: batch.id,
      type: InventoryMovementType.received,
      quantityDelta: request.quantity,
      occurredAt: now,
      createdAt: now,
      idempotencyKey: request.idempotencyKey,
    );

    try {
      final updatedProduct = Product(
        id: product.id,
        shopId: product.shopId,
        name: product.name,
        brand: product.brand,
        category: product.category,
        imageUrl: product.imageUrl,
        source: product.source,
        sourceReference: product.sourceReference,
        catalogProductId: product.catalogProductId,
        sellingPriceMinor: request.sellingPriceMinor,
        barcode: product.barcode,
        packagingDisplay: product.packagingDisplay,
        createdAt: product.createdAt,
        updatedAt: now,
        isArchived: product.isArchived,
      );
      final stagedProducts = Map<String, Product>.of(_products)..[product.id] = updatedProduct;
      final stagedBatches = List<Batch>.of(_batches)..add(batch);
      _onTransactionStage?.call(ReceivingTransactionStage.batchStaged);

      final stagedMovements = List<InventoryMovement>.of(_movements)..add(movement);
      _onTransactionStage?.call(ReceivingTransactionStage.movementStaged);

      final stagedReceivings = Map<String, _StoredReceiving>.of(_receivings)
        ..[receiptKey] = _StoredReceiving(request: request, batch: batch, movement: movement);

      // No await or fallible work occurs while publishing the staged state.
      _products = stagedProducts;
      _batches = stagedBatches;
      _movements = stagedMovements;
      _receivings = stagedReceivings;
    } on InventoryRepositoryException {
      rethrow;
    } catch (error) {
      throw InventoryRepositoryException(
        InventoryRepositoryFailureKind.unavailable,
        'Received stock could not be saved atomically.',
        cause: error,
      );
    }

    return ReceivingReceipt(batch: batch, movement: movement, wasDuplicate: false);
  }
}

int _compareDashboardBatches(Batch left, Batch right) {
  final leftExpiry = left.expiryDate;
  final rightExpiry = right.expiryDate;
  if (leftExpiry == null && rightExpiry != null) return 1;
  if (leftExpiry != null && rightExpiry == null) return -1;
  if (leftExpiry != null && rightExpiry != null) {
    final expiryComparison = leftExpiry.compareTo(rightExpiry);
    if (expiryComparison != 0) return expiryComparison;
  }
  final receivedComparison = left.createdAt.compareTo(right.createdAt);
  if (receivedComparison != 0) return receivedComparison;
  return left.id.compareTo(right.id);
}

final class _StoredReceiving {
  const _StoredReceiving({required this.request, required this.batch, required this.movement});

  final ReceivingRequest request;
  final Batch batch;
  final InventoryMovement movement;
}

DateTime _systemUtcClock() => DateTime.now().toUtc();
