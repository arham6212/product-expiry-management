# Vertical-Slice Roadmap

Each bullet is a candidate slice, not a single large release. A slice must ship
behavior, tests, and documentation together.

For the audited Android pilot critical path, task order, priority, and exact
verification commands, use `docs/release-plan.md`. This roadmap remains the
longer-term capability map.

## Phase 0 — Foundation

- Project conventions, architecture, agent workflow, logging, errors, and
  environment configuration.
- PostgreSQL/backend direction and safe migration principles documented;
  persistence dependencies deferred until the first inventory slice.
- Application shell and navigation; the current Home remains demo data until
  the expiry-dashboard release slice replaces it.
- Initial provider-independent domain records and date-only primitive.
- Formatting, static analysis, unit/widget tests, and build verification.

## Phase 1 — Core inventory domain

- **Delivered for catalog:** authenticated shops, memberships, Product,
  ProductBarcode, Batch, and InventoryMovement Supabase migrations/RLS.
- **Delivered:** manual Product creation for a scanned barcode, plus repository
  support for a normalized shop-owned Product with no barcode or guessed global
  identity. Receiving can create, select, and continue with that barcode-less
  Product without clearing the Batch draft.
- **Delivered:** in-memory manual receiving for an existing product, atomically
  creating a batch plus `RECEIVED` movement with idempotent retries.
- **Delivered:** authenticated shop-owned Batch/InventoryMovement persistence,
  atomic receiving RPC, required new-receive expiry, optional lot input, and
  resolved-Product handoff. Historical unknown-expiry rows remain nullable.
- **Delivered for receiving:** initial quantity projection and
  duplicate/idempotency protection. Later quantity changes and reconciliation
  remain in the release plan.

## Phase 1B — Customer storefront foundation

- **Delivered:** anonymous Explore, public shop storefront, Product search,
  Product details, published selling prices, and active deal display.
- **Delivered:** dedicated public profile/listing/deal schema with server-time
  RLS, owner/manager publication management, and no private inventory grants.
- **Delivered foundation:** separate global CatalogProduct identity and optional
  shop Product relationship without unsafe automated backfill.
- Next: reviewed global-catalog matching and image-management workflow; do not
  infer matches or expose stock as part of that slice.

## Phase 2 — Expiry engine

- Deterministic `ExpiryRiskService` with boundary/timezone tests.
- Batch status and query for the daily action queue.
- Action-oriented home screen for expired and upcoming batches.

## Phase 3 — Barcode receiving

- Scanner adapter and permission/error UX.
- **Delivered prerequisite:** database-first product resolution, Open Food Facts
  cache-miss provider, persistent external hits, and unknown-product fallback
  states through temporary manual barcode entry.
- Resumable continuous receiving session.

## Phase 4 — Expiry OCR

- Camera capture and provider adapter.
- Candidate extraction, date-type interpretation, and confidence policy.
- Explicit confirmation/correction UX and observation audit record.

## Phase 5 — Smart receiving

- Combine barcode and expiry capture.
- Skip already-known fields safely.
- Implement and test the receiving state machine and scan-next loop.

## Phase 6 — FEFO and actions

- Deterministic FEFO recommendations.
- Typed sold, discounted, returned, disposed, and kept actions.
- Atomic movement/action recording.

## Phase 7 — Notifications

- Local and push provider adapters.
- Configurable windows, quiet hours, permission states, and deduplication.

## Phase 8 — Analytics

- Stock at risk, expired value, waste, returned/discounted value.
- Clearly defined estimated prevented-loss metric with provenance.

## Phase 9 — Suppliers

- Supplier assignment and return-policy deadlines.
- Return opportunity in queue and auditable supplier-return workflow.

## Phase 10 — Commercial features

- Plan limits and unlimited inventory.
- Staff accounts and multiple branches.
- Advanced reports, exports, and WhatsApp/SMS integrations.

## Release discipline

Do not start a later phase merely because its types are convenient. Pull forward
only the smallest prerequisite with a documented reason. Authentication,
schema changes, and offline synchronization each require explicit threat,
migration, and failure-mode review.
