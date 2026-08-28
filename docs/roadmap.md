# Vertical-Slice Roadmap

Each bullet is a candidate slice, not a single large release. A slice must ship
behavior, tests, and documentation together.

## Phase 0 — Foundation

- Project conventions, architecture, agent workflow, logging, errors, and
  environment configuration.
- Application shell and navigation with a home placeholder.
- Initial provider-independent domain records and date-only primitive.
- Formatting, static analysis, unit/widget tests, and build verification.

## Phase 1 — Core inventory domain

- Persist shop, product, barcode, and batch locally/backend with migrations.
- Manual product creation.
- Manual receiving transaction that creates a batch plus `RECEIVED` movement.
- Quantity projection, reconciliation, and duplicate/idempotency protection.

## Phase 2 — Expiry engine

- Deterministic `ExpiryRiskService` with boundary/timezone tests.
- Batch status and query for the daily action queue.
- Action-oriented home screen for expired and upcoming batches.

## Phase 3 — Barcode receiving

- Scanner adapter and permission/error UX.
- Local product resolution and unknown-product flow.
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

