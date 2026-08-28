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

