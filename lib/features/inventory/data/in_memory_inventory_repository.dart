import '../../../core/identity/local_id_generator.dart';
import '../../../domain/entities/domain_models.dart';
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
  }) : _products = {for (final product in products) product.id: product},
       _batches = List<Batch>.of(batches),
       _movements = List<InventoryMovement>.of(movements),
       _onTransactionStage = onTransactionStage,
       _idGenerator = idGenerator ?? LocalIdGenerator.next,
       _clock = clock ?? _systemUtcClock;

  final Map<String, Product> _products;
  List<Batch> _batches;
  List<InventoryMovement> _movements;
  Map<String, _StoredReceiving> _receivings = {};
  final TransactionStageObserver? _onTransactionStage;
  final EntityIdGenerator _idGenerator;
  final UtcClock _clock;

  List<Batch> get batches => List.unmodifiable(_batches);
  List<InventoryMovement> get movements => List.unmodifiable(_movements);

  @override
  Future<List<Product>> listProducts({required String shopId}) async {
    final products = _products.values.where((product) => product.shopId == shopId).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    return List.unmodifiable(products);
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
      final stagedBatches = List<Batch>.of(_batches)..add(batch);
      _onTransactionStage?.call(ReceivingTransactionStage.batchStaged);

      final stagedMovements = List<InventoryMovement>.of(_movements)..add(movement);
      _onTransactionStage?.call(ReceivingTransactionStage.movementStaged);

      final stagedReceivings = Map<String, _StoredReceiving>.of(_receivings)
        ..[receiptKey] = _StoredReceiving(request: request, batch: batch, movement: movement);

      // No await or fallible work occurs while publishing the staged state.
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

final class _StoredReceiving {
  const _StoredReceiving({required this.request, required this.batch, required this.movement});

  final ReceivingRequest request;
  final Batch batch;
  final InventoryMovement movement;
}

DateTime _systemUtcClock() => DateTime.now().toUtc();
