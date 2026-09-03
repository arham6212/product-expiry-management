# Architecture Decision Log

Entries are append-only. Supersede a decision with a new ADR rather than
rewriting history after implementation depends on it.

## ADR-001 — Expiry belongs to Batch rather than Product

- **Status:** Accepted
- **Decision:** Store the authoritative expiry date on `Batch`; `Product` has no
  expiry field.
- **Reason:** The same product can be received in multiple lots with different
  expiry dates. Product-level expiry would overwrite valid inventory data.

## ADR-002 — Barcode primarily resolves Product identity

- **Status:** Accepted
- **Decision:** Use ordinary barcode data to resolve products. Treat batch or
  expiry data as present only for a supported structured barcode format.
- **Reason:** Most retail codes describe a catalog item, not a physical batch.

## ADR-003 — OCR suggestions require validation before persistence

- **Status:** Accepted
- **Decision:** Persist a recognized date as authoritative only after the
  confidence/date-type policy permits it and required user confirmation occurs.
- **Reason:** Misread expiry data can corrupt operational decisions and waste
  stock.

## ADR-004 — Known rules use deterministic services

- **Status:** Accepted
- **Decision:** Implement expiry risk, FEFO, quantities, and date interpretation
  as deterministic, tested code rather than LLM reasoning.
- **Reason:** Known business rules must be repeatable, explainable, and testable.

## ADR-005 — Isolate external providers behind small interfaces

- **Status:** Accepted
- **Decision:** Define narrow ports for product lookup, barcode scanning, expiry
  recognition, and notifications; keep provider DTOs in adapters.
- **Reason:** Providers have different availability, privacy, and commercial
  constraints and must be replaceable.

## ADR-006 — Develop through vertical slices

- **Status:** Accepted
- **Decision:** Deliver one end-to-end behavior at a time with its tests and
  documentation.
- **Reason:** Small slices are safer to review and easier for future agents to
  complete autonomously.

## ADR-007 — Flutter client with managed PostgreSQL backend

- **Status:** Accepted for architecture; backend not installed in Phase 0
- **Decision:** Retain Flutter for clients and target Supabase-managed PostgreSQL,
  Auth, and narrowly scoped server functions.
- **Reason:** The existing codebase is Flutter, while relational transactions,
  row-level authorization, and a managed platform suit a small product team.

## ADR-008 — Movement ledger plus transactional quantity projection

- **Status:** Accepted for future persistence
- **Decision:** Treat append-only `InventoryMovement` rows as audit history and
  maintain `Batch.currentQuantity` atomically as a query projection.
- **Reason:** This provides fast mobile queries without losing provenance.
  Reconciliation detects projection drift.

## ADR-009 — Calendar-date expiry value

- **Status:** Accepted
- **Decision:** Represent expiry as a validated date without time-of-day or UTC
  conversion; evaluate it relative to the shop timezone.
- **Reason:** Expiry labels are calendar dates. Treating them as instants can
  shift the visible date across timezones.

## ADR-010 — Receiving transaction lives behind the inventory repository

- **Status:** Accepted
- **Decision:** `ReceiveExistingProduct` orchestrates validation and entity
  creation, while `InventoryRepository.commitReceiving` atomically revalidates
  the product, handles idempotency, and publishes the batch plus movement.
  Phase 1 uses an in-memory adapter that stages complete replacement state; a
  future PostgreSQL adapter must use one database transaction and unique key.
- **Reason:** UI-level guarding cannot protect inventory from retries or partial
  persistence. Keeping one explicit commit boundary makes the invariant
  enforceable and keeps storage replaceable without prematurely adding an SDK.

## ADR-011 — Idempotency conflicts are rejected

- **Status:** Accepted
- **Decision:** Retrying the same key with identical product, expiry, and
  quantity returns the original result. Reusing it with any different input
  throws `IdempotencyConflictException` and performs no write.
- **Reason:** Returning an unrelated earlier result would conceal caller bugs;
  processing the second request would double-count or corrupt inventory.

## ADR-012 — Initialize the Supabase client at the composition root

- **Status:** Accepted
- **Decision:** Use `supabase_flutter` to initialize one client in the guarded
  application bootstrap from `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`
  compile-time values. Await initialization before `runApp`; do not expose SDK
  calls to widgets or replace the current repositories in this slice.
- **Reason:** Supabase's SDK owns the cross-platform Flutter initialization and
  client lifecycle that platform APIs do not provide. Keeping it at the
  composition root preserves the existing inward dependency direction and
  defers persistence and authentication boundaries until their own slices.

## ADR-013 — Shop membership is the product-catalog authorization boundary

- **Status:** Accepted
- **Decision:** Use `auth.users` for identity, `shops` for tenants, and
  `shop_memberships(shop_id, user_id)` for access. Product and ProductBarcode
  remain shop-owned. Every exposed table enables RLS, `anon` receives no grants,
  and authenticated access requires membership through `auth.uid()`.
- **Reason:** A client-selected shop ID is routing context, not proof of
  authorization. Database membership policies and composite cross-shop foreign
  keys provide defense in depth without a privileged Flutter credential.

## ADR-014 — Product resolution is database-first with a provider boundary

- **Status:** Accepted
- **Decision:** `ResolveProductByBarcode` checks the current shop catalog before
  calling `ProductLookupProvider`. Open Food Facts is the first adapter and is
  never called for a known shop barcode. Provider, HTTP, and Supabase types stay
  outside domain and presentation layers.
- **Reason:** The shop catalog is the persistent cache, so ordinary scans remain
  fast, available, and within provider rate limits while the external provider
  stays replaceable.

## ADR-015 — External barcode caching is atomic and race-safe

- **Status:** Accepted
- **Decision:** Enforce `UNIQUE (shop_id, barcode)` and create external Product
  plus ProductBarcode through one security-invoker PostgreSQL function. The
  function takes a transaction advisory lock, rechecks the mapping, and returns
  the existing winner when another request saved first.
- **Reason:** A client lock cannot protect multiple devices. Inserting Product
  and barcode separately can also leave duplicate/orphan Product rows after a
  uniqueness conflict.

## ADR-016 — Require a usable external product name

- **Status:** Accepted
- **Decision:** Automatically cache only a normalized requested barcode plus a
  non-blank product or generic name. Brand and HTTP(S) image URL are optional;
  nutrition, ingredients, quantity, categories, and expiry-like provider data
  are not persisted. Source is the domain value `OPEN_FOOD_FACTS`.
- **Reason:** Barcode plus a usable name is the minimum catalog identity needed
  by receiving. Saving incomplete or unrelated provider fields would create
  unusable products and blur Product/Batch ownership.

## ADR-017 — Receive stock through one shop-authorized PostgreSQL function

- **Status:** Accepted
- **Decision:** Persist a Batch and its initial `RECEIVED` InventoryMovement
  through `receive_product_stock`. Flutter supplies the selected shop explicitly,
  while the function independently checks `auth.uid()`, membership, and
  same-shop Product ownership. Receiving tables grant member-scoped reads but
  no direct client mutations. The function serializes on the shop/idempotency
  pair, with `UNIQUE (shop_id, idempotency_key)` as the database backstop.
- **Reason:** UI submission guards and client locks cannot prevent duplicates
  across devices or partial Batch/movement persistence. A narrowly granted
  transaction is the smallest authoritative integrity boundary.

## ADR-018 — Allow explicitly unknown expiry when receiving

- **Status:** Accepted
- **Decision:** `Batch.expiryDate` is nullable for receiving. Absence means
  unknown; it is never replaced with a guessed value. Quantity remains required
  and positive, while lot number is optional and whitespace-normalized.
- **Reason:** The production receiving requirement permits stock to be recorded
  before an expiry is known. Rejecting it or inventing a date would either lose
  inventory or corrupt expiry decisions. A later audited capture/correction
  slice can supply the missing date.

## ADR-019 — Use Riverpod for client workflow state and composition overrides

- **Status:** Accepted
- **Decision:** Install one root `ProviderScope`; expose the existing dependency
  graph through override-required providers; and use Riverpod `StreamProvider`,
  `Notifier`, and `AsyncNotifier` controllers for authentication, active-shop
  session, shell navigation, Product resolution, and stock receiving. Keep
  text/form controllers in lifecycle-aware consumer widgets. Do not add code
  generation, hooks, Freezed, or another state-management library.
- **Reason:** The workflows now contain identity-driven tenant selection,
  asynchronous progress/failure states, and retry/idempotency state that should
  survive widget rebuilds and be independently testable. Provider overrides
  preserve the existing composition root and inward dependency direction;
  Riverpod remains a presentation/application concern and does not enter domain,
  repository, Supabase, or RLS contracts.

## ADR-020 — Use qr_flutter and mobile_scanner for join-code sharing

- **Status:** Accepted
- **Decision:** Use `qr_flutter ^4.1.0` to render owner invitations and
  `mobile_scanner ^7.4.0` to scan them. The payload is exactly
  `shop-invite:<CODE>` and never contains a shop ID, user ID, email, credential,
  or token. A pure Dart utility owns encoding/parsing. An auto-disposed Riverpod
  controller owns accepted/invalid/retry and duplicate-detection state, while
  the widget owns the camera controller and navigation. A scan only returns the
  normalized code to the existing form; explicit confirmation invokes the same
  `requestToJoinShop(code)` operation as manual entry. `share_plus ^13.3.0`
  shares text/code only; the product does not claim QR-image export.
- **Reason:** Flutter platform APIs do not natively generate, scan, or invoke a
  portable text share sheet for this workflow. These versions resolve under the
  repository's Dart constraint and installed Flutter toolchain. QR is only a
  transport convenience: PostgreSQL remains authoritative for authentication,
  invalid/expired/revoked codes, pending-request uniqueness, and one-shop
  membership. This separation keeps camera/plugin behavior out of membership
  rules and makes duplicate scans independently testable.

## ADR-021 — Keep one time-bounded active invite per shop

- **Status:** Accepted
- **Decision:** Persist a seven-day `expires_at` on each invite, enforce at most
  one active invite row per shop with a partial unique index, and serialize owner
  enable/disable and rotation RPCs. Rotation deactivates every older code.
  Re-enabling restores only the newest unexpired valid code or creates a new one.
- **Reason:** Treating every historical row as active when joining was re-enabled
  revived revoked credentials and made the rendered QR nondeterministic. The
  invariant belongs in PostgreSQL because all clients and races must observe the
  same authority; client filtering alone cannot protect membership creation.

## ADR-022 — Manual Product entry shares the barcode persistence lock

- **Status:** Accepted
- **Decision:** Preserve the scanned barcode when external resolution cannot
  supply a usable Product. Manual entry requires a normalized non-blank name and
  saves through `create_manual_product_for_barcode`, which delegates to
  `create_product_for_barcode` so manual/external retries and races use the same
  transaction advisory lock and existing `(shop_id, barcode)` uniqueness
  constraint. The persisted winner is always returned to the client.
- **Reason:** A placeholder or two client inserts could leave incomplete,
  duplicate, or orphaned catalog data. Sharing the established transaction
  boundary completes the fallback without introducing a second race policy.

## ADR-023 — Publish through a separate customer-safe storefront schema

- **Status:** Accepted
- **Decision:** Keep `products` as the shop-owned inventory identity. Add a
  separate global CatalogProduct with an optional Product link, plus dedicated
  PublicShopProfile, PublishedProductListing, and Deal tables. Customer reads
  receive grants only on those three publication tables and are constrained by
  opt-in and PostgreSQL-time RLS. Owners and managers manage their shop;
  workers do not. Existing Products are not automatically linked globally.
- **Reason:** Reinterpreting or exposing the existing Product would leak a
  private tenant boundary into the marketplace and risk breaking barcode,
  Batch, and movement references. Explicit publication is auditable, supports
  public overrides/prices without duplicating inventory identity, and leaves a
  safe seam for future catalog matching and batch-specific promotions.

## ADR-024 — Use the listing price as a deal's normal price

- **Status:** Accepted
- **Decision:** A Deal stores its offer price and references exactly one
  PublishedProductListing, whose price is the authoritative normal price.
  Database triggers require offer < normal, reject a listing-price change that
  invalidates an enabled offer, and prevent overlapping enabled windows.
- **Reason:** Duplicating normal price on every deal would let customer-visible
  prices disagree. The relational invariant supplies both prices while keeping
  the Phase 1 offer model small.

## ADR-025 — Require expiry for new manual receiving

- **Status:** Accepted; supersedes ADR-018 for new manual receives only.
- **Decision:** `ReceiveStock` and `receive_product_stock` reject a missing
  expiry before creating inventory. `Batch.expiryDate` and
  `batches.expiry_date` remain nullable so historical unknown-expiry records are
  readable and untouched. No date is inferred or backfilled.
- **Reason:** The Android pilot requires Product, expiry, and quantity for every
  new manual receive. Enforcing this in both application code and PostgreSQL
  prevents UI bypass while preserving existing inventory safely.

## ADR-026 — Restrict private Shop row updates to owners

- **Status:** Accepted.
- **Decision:** Keep authenticated member SELECT access to the private `shops`
  row, but require a same-shop `owner` membership in both the `USING` and `WITH
  CHECK` expressions of its UPDATE policy. Managers and workers retain their
  unrelated operational permissions. Public storefront profile permissions are
  unchanged because publication metadata is a separate table and boundary.
- **Reason:** Tenant identity and configuration currently share one private Shop
  row. Until a specific manager settings permission is approved, owner-only RLS
  is the smallest server-authoritative rule and cannot be bypassed through a
  lower-level client request.

## ADR-027 — Change operational roles through one owner-only RPC

- **Status:** Accepted.
- **Decision:** Keep direct `shop_memberships` mutation unavailable to clients.
  Expose `update_shop_member_role(shop, user, role)` only to `authenticated` as
  an empty-search-path `SECURITY DEFINER` function. It authorizes the caller as
  same-shop owner, locks the exact target membership, accepts only `manager` or
  `worker`, and rejects self-demotion and every owner-role mutation.
- **Reason:** Role authorization and ownership invariants must survive UI bypass
  and concurrent requests. A locked, narrowly granted server operation prevents
  cross-tenant changes and duplicate/moved memberships without introducing
  ownership transfer or broad membership update grants.
- **Recovery:** The matching down script removes the RPC and its execute
  surface. Already-persisted role changes are business data and require an
  explicit audit before manual correction; rollback never guesses prior roles.
