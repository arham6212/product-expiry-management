# Domain Model

## Modeling conventions

Domain entities have stable IDs. Shop-owned entities carry `shopId` explicitly.
Business timestamps are UTC instants; expiry is a date-only value interpreted
using `Shop.timeZone`. `createdAt` is immutable. `updatedAt` changes only when a
mutable field changes. Initial entities are immutable values in the client;
persistence and mutation use cases arrive in later slices.

Soft deletion is represented as archival only where historical references must
remain readable. Movement and action history is append-only and is never soft
deleted during ordinary operation.

## Entities

### User

- **Identity:** stable authentication-aligned `id`.
- **Fields:** display name, email, creation/update timestamps.
- **Ownership:** a user can belong to shops through a future `ShopMembership`.
- **Lifecycle:** created with authentication; personal fields are mutable.
- **Deletion:** account erasure is a later security/privacy workflow; historical
  operational records should be anonymized rather than broken.

### Shop

- **Identity:** stable `id`.
- **Fields:** name, IANA timezone, three-letter currency, timestamps, archive
  state.
- **Ownership:** top-level tenant; products, batches, suppliers, movements, and
  actions belong to one shop.
- **Lifecycle:** mutable settings; archival preserves records.

### Product

- **Identity:** shop-local `id`; a future optional shared-catalog reference is
  metadata, not identity.
- **Fields:** `shopId`, name, optional brand/category, timestamps, archive state.
- **Relationships:** has many barcodes and batches.
- **Invariant:** it has no expiry field. Expiry is batch-specific.
- **Lifecycle:** names/metadata are mutable; archive instead of deleting when
  batches or movements exist.

### ProductBarcode

- **Identity:** stable `id`.
- **Fields:** `shopId`, `productId`, normalized code, symbology, primary flag,
  timestamps.
- **Relationships:** many barcodes may identify one product. Within a shop, a
  normalized active code resolves to at most one product unless a structured
  code explicitly has different semantics.
- **Lifecycle:** may be corrected or deactivated; preserve audit metadata.

### Batch

- **Identity:** stable `id`, not `(product, expiry)`. Separate deliveries can
  share an expiry and still be distinct when lot/supplier/cost differs.
- **Fields:** `shopId`, `productId`, required expiry date, optional lot code and
  supplier, cached current quantity, optional unit cost/currency, timestamps,
  archive state.
- **Relationships:** belongs to one product; has many movements, observations,
  and actions.
- **Invariant:** a product can have many active batches. New stock with a new
  expiry creates a new batch and never mutates an old batch's expiry.
- **Mutability:** expiry correction requires an explicit audited use case; cached
  quantity changes only with a committed movement.
- **Deletion:** archive only after quantity is zero; history remains.

### InventoryMovement

- **Identity:** stable client-generated `id`; `idempotencyKey` is unique per
  shop operation.
- **Fields:** `shopId`, `batchId`, typed movement kind, signed quantity delta,
  occurrence/creation timestamps, optional reason/reference.
- **Kinds:** `RECEIVED`, `SOLD`, `DISPOSED`, `RETURNED`, `ADJUSTED`.
- **Lifecycle:** append-only. Corrections are compensating movements, not edits.
- **Quantity model:** movement history is the audit source of truth, while
  `Batch.currentQuantity` is a transactionally maintained projection for fast
  queues and FEFO reads. Every write inserts the movement and updates the batch
  projection atomically. Periodic reconciliation can detect drift. This avoids
  expensive sums on every mobile view without sacrificing auditability.

### ExpiryObservation

- **Identity:** stable `id`, created before or after a batch is persisted.
- **Fields:** optional `batchId`, source (`STRUCTURED_BARCODE`, `OCR`, `MANUAL`),
  candidate date, detected date type, confidence, raw text, confirmation state,
  observation timestamp.
- **Lifecycle:** immutable evidence. An observation does not become authoritative
  simply because it exists; persistence workflow records explicit confirmation.
- **Privacy:** raw OCR text may contain unrelated text and needs bounded
  retention/redaction.

### ExpiryAction

- **Identity:** stable `id`.
- **Fields:** `shopId`, `batchId`, typed action, affected quantity, occurrence
  timestamp, optional note/reference.
- **Kinds:** `SOLD`, `DISCOUNTED`, `RETURNED_TO_SUPPLIER`, `DISPOSED`, `KEPT`.
- **Lifecycle:** append-only. Quantity-changing actions link to the corresponding
  inventory movement; `KEPT` records a reviewed decision without changing stock.

### Supplier

- **Identity:** stable shop-local `id`.
- **Fields:** `shopId`, name, optional contact data, timestamps, active state.
- **Relationships:** optionally assigned to batches; future policies model return
  windows rather than overloading the supplier record.
- **Lifecycle:** mutable contact data; deactivate instead of delete when used.

## Future supporting concepts

- `ShopMembership` for roles and multi-user authorization.
- `ReceivingSession`/`ReceivingDraft` for resumable scanner state.
- `SupplierReturnPolicy` for deadlines and eligibility.
- Domain services such as `ExpiryRiskService` and `FefoOrderingService` for
  deterministic rules.

These are deliberately not implemented until their vertical slice supplies
acceptance criteria.

