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
- **Ownership:** a user belongs to at most one shop through `ShopMembership`.
- **Lifecycle:** created with authentication; personal fields are mutable.
- **Deletion:** account erasure is a later security/privacy workflow; historical
  operational records should be anonymized rather than broken.

### Shop

- **Identity:** stable `id`.
- **Fields:** name, IANA timezone, three-letter currency, timestamps, archive
  state.
- **Ownership:** top-level tenant; products, batches, suppliers, movements, and
  actions belong to one shop.
- **Lifecycle:** private settings are mutable only by the Shop owner; archival
  preserves records.

### Product

- **Identity:** shop-local `id`; optional `catalogProductId` links to a separate
  platform-wide identity but never replaces the shop-owned ID.
- **Fields:** `shopId`, name, optional brand/category, timestamps, archive state.
- **Metadata:** optional external image URL, provider-independent source
  (`LOCAL_MANUAL` or `OPEN_FOOD_FACTS`), and optional source reference.
- **Relationships:** has zero or many barcodes and has many batches. A manual
  shop-owned Product does not need an invented barcode identity.
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
- **Constraint:** the persisted catalog owns one mapping per `(shopId,
  normalized code)` and cannot reference a Product from another shop.
- **Lifecycle:** may be corrected or deactivated; preserve audit metadata.

### Batch

- **Identity:** stable `id`, not `(product, expiry)`. Separate deliveries can
  share an expiry and still be distinct when lot/supplier/cost differs.
- **Fields:** `shopId`, `productId`, nullable expiry date, optional lot code and
  supplier, cached current quantity, optional unit cost/currency, timestamps,
  archive state.
- **Relationships:** belongs to one product; has many movements, observations,
  and actions.
- **Invariant:** a product can have many active batches. New stock with a new
  expiry creates a new batch and never mutates an old batch's expiry.
- **Unknown expiry:** historical rows may have expiry absent and remain readable
  without backfill or invention. Every new manual receive requires a validated
  expiry date. A later audited correction workflow may address historical
  unknown-expiry rows separately.
- **Mutability:** expiry correction requires an explicit audited use case; cached
  quantity changes only with a committed movement.
- **Receiving quantity:** manual receiving accepts 1 through 2,147,483,647. Zero,
  negative, and larger values are rejected before a transaction begins.
- **Deletion:** archive only after quantity is zero; history remains.

### InventoryMovement

- **Identity:** stable client-generated `id`; `idempotencyKey` is unique per
  shop operation.
- **Fields:** `shopId`, `batchId`, typed movement kind, signed quantity delta,
  occurrence/creation timestamps, optional reason/reference.
- **Kinds:** `RECEIVED`, `SOLD`, `DISPOSED`, `RETURNED`, `ADJUSTED`.
- **Lifecycle:** append-only. Corrections are compensating movements, not edits.
- **Idempotency:** an exact retry returns the originally committed records. A
  reused key with a different product, expiry, quantity, or lot number is an explicit
  conflict and cannot alter stock.
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

### ShopMembership

- **Identity:** composite `(shopId, userId)`.
- **Fields:** shop, Supabase-auth user ID, role (`OWNER`, `MANAGER`, or `WORKER`), creation
  timestamp.
- **Authorization:** membership is the database source for shop-owned RLS. Users
  read their own membership; owners can review join requests and the team roster
  through narrowly authorized functions. Only an owner may change an existing
  non-owner membership between `MANAGER` and `WORKER`; the operation cannot
  transfer ownership, change Shop identity, or mutate an owner membership.

### ShopInvite

- **Identity:** stable ID with a globally unique six-character alphanumeric code.
- **Fields:** shop, normalized code, active flag, creator, creation instant, and
  expiry instant.
- **Invariant:** at most one invite row is active per shop. Active is necessary
  but not sufficient for use: the server also requires `expiresAt` to be in the
  future.
- **Lifecycle:** rotation permanently deactivates older codes and creates a new
  seven-day invite. Disabling deactivates the current invite; enabling restores
  only the newest usable invite or creates a replacement.

### ShopJoinRequest

- **Identity:** stable ID linking a requesting auth user to the resolved shop.
- **Fields:** shop, user, status (`PENDING`, `APPROVED`, or `REJECTED`), creation
  instant, and optional reviewer metadata.
- **Invariant:** a user may have only one pending request and may be a member of
  only one shop. Approval creates a `WORKER` membership.
- **QR boundary:** QR data is only `shop-invite:<CODE>`. Detection selects the
  code for review; it never creates a request without explicit confirmation.

### CatalogProduct

- **Identity:** platform-wide `id`, independent of any shop.
- **Fields:** canonical public name, optional brand/image, source and source
  reference, timestamps, and globally unique barcode mappings.
- **Relationship:** a shop-owned Product may optionally reference one
  CatalogProduct. Existing Products remain unlinked until a deterministic or
  reviewed matching workflow exists.
- **Privacy:** the current client has no direct catalog-curation grants. Public
  listings remain usable without this optional relationship.

### PublicShopProfile

- **Identity:** one row per private Shop, keyed by `shopId`.
- **Fields:** explicitly public display name, optional description/logo/area,
  enabled flag, and timestamps.
- **Invariant:** creation of a Shop creates a disabled profile. A Shop is absent
  from customer reads until an owner or manager enables it.
- **Privacy:** it contains no owner/member identity or private Shop settings.

### PublishedProductListing

- **Identity:** stable ID, unique for `(shopId, productId)`.
- **Fields:** public display name/description/image, positive selling price in
  integer minor units, currency, published flag, and timestamps.
- **Relationship:** references a shop-owned Product through a same-shop
  composite foreign key; it does not expose that Product row to customers.
- **Invariant:** inventory existence never publishes a listing. A customer sees
  it only when both listing and storefront are enabled.

### Deal

- **Identity:** stable shop-owned ID for one PublishedProductListing.
- **Fields:** positive offer price, half-open `[startsAt, endsAt)` window,
  enabled flag, optional public title/description, and timestamps. Normal price
  is the related listing's selling price.
- **Invariants:** offer is below normal price, start precedes end, and enabled
  windows for one listing do not overlap.
- **Visibility:** customer reads use PostgreSQL server time and require an
  enabled storefront plus published listing. Deactivation, future start, or
  expiry removes the row from customer reads automatically.
- **Future batch link:** no Batch is linked or advertised in this slice. A later
  explicit batch-promotion entity can attach operational provenance without
  weakening public RLS.

## Future supporting concepts

- `ReceivingSession`/`ReceivingDraft` for resumable scanner state.
- `SupplierReturnPolicy` for deadlines and eligibility.
- Domain services such as `ExpiryRiskService` and `FefoOrderingService` for
  deterministic rules.

These are deliberately not implemented until their vertical slice supplies
acceptance criteria.
