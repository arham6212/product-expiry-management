# Current Task

## 2026-09-05 — Production-safe product image contributions

Implement a production-ready optional product-image flow for scanning and
receiving. A signed-in shop member may select, resize, and upload a JPEG, PNG,
or WebP only for a CatalogProduct already linked to that shop. The backend must
derive the user from the JWT, verify membership and the Product relationship,
inspect authoritative Cloudinary metadata, and create a pending contribution.
Only the backend/service role may approve a contribution or change the global
canonical image.

### Approved scope

- Harden the deployed image-contribution schema and both Cloudinary Edge
  Functions without exposing vendor or Supabase secrets to Flutter.
- Add repository/picker/processor boundaries, Riverpod workflow state, and a
  reusable product-image card to the resolved-product, manual-product, and
  receiving flows.
- Keep image upload optional: selection, permission, network, verification, or
  contribution failure must not corrupt or block Product creation or receiving.
- Add focused database, Edge Function, Dart, and widget tests; document the
  dependency and trust-boundary decisions; verify and commit only this slice.

### Out of scope

- Automatic approval or canonical-image promotion by authenticated clients.
- Attaching an unverified upload to a global product, or inventing a global
  image relationship for barcode-less/shop-only Products.
- Price, expiry, Batch, movement, crawler, Ansar workbook/state, storefront, or
  catalog-ingestion behavior changes.
- Deploying the new migration/functions or configuring Cloudinary secrets; the
  completion report must identify those manual production steps.

### Status

Completed on 2026-09-06. The focused Flutter image flow is implemented and
verified. The blocking client-metadata trust defect was fixed by deploying the
follow-up hardening migration and both existing Cloudinary Edge Functions to
the linked Supabase project.

## 2026-09-04 — Ansar catalog synchronization

Implement, deploy, backfill, and enable the production-safe synchronization of
the persistent Ansar workbook into the global Supabase catalog. Ingestion must
remain service-only, idempotent, and unable to create or mutate shop Products,
Batches, expiry, prices, inventory movements, listings, or deals. The scan path
may read safe global catalog fields and may create or attach a shop Product only
after explicit user confirmation.

The implementation, deployment, initial production backfill, and GitHub Actions
verification completed successfully in run `33916764979`. The workflow committed
the durable catalog state in `3b2a92a`.

## Objective

Materialize and verify the reviewed first global-catalog compatibility migration,
after resolving the undeployed mandatory-selling-price migration and completing
the linked read-only preflight.

## Approved scope

- Verify `20260903225832_require_receive_selling_price.sql` locally and leave it
  undeployed.
- Preserve both existing public barcode-creation RPC signatures and result
  shape while resolving one global CatalogProduct identity per barcode.
- Keep each Shop's Product as the inventory identity, attach legacy NULL links
  lazily, preserve provenance, and protect catalog identity mutation.
- Add focused pgTAP, concurrency, rollback, Flutter compatibility, lint, and
  linked dry-run verification.
- Add focused Home and navigation tests, including Shop-switch and compact-phone
  behavior.

## Out of scope

- Cloudinary, image-contribution storage, or the reviewed Migration 2.
- Backfilling existing Products, changing Product/Batch/Movement IDs, or
  enabling the storefront.
- Deployment, production data mutation, application feature work, or commit.

## Status

Implementation and all requested local/linked dry-run verification completed on
2026-09-04. Both reviewed migrations are ready for a separately authorized
deployment; no deployment was performed.

## 2026-09-06 — Shopkeeper scanning workflow

Plan: consolidate scan resolution into a direct receiving handoff; review global/unknown metadata once; keep lookup failures retryable; expose images in receiving; retain photo state while receiving; add scan-next success action; guard scanner and pending-save back lifecycle. Preserve price, explicit quantity, expiry, atomic movement and backend contracts. Verify focused widget/application tests, analyzer and build. No deploy or commit.

### Workflow implementation status

Implemented and reviewed. Formatting, analyzer, 111 focused tests and Android
debug build pass. No backend changes, deployment or commit. See the dated
implementation notes for files, emulator checks and remaining physical-device
verification.

## Focused Receive Stock follow-up

Plan: allow SQL/Dart null receiving quantity with an audited received movement; include unknown quantity in expiry reads; retain quantity signs for all other movements. Preserve existing data and RPC signatures. Move barcode-less creation to scanner, show metadata/shop currency, compact approved/pending photos, collapse lot details and pin Save stock above keyboard. Focused tests/analyzer/build only; deploy just the reviewed migration to linked Supabase. No device/manual tests or commit.

Focused follow-up completed: 116 Flutter tests, 77 local SQL assertions,
format/analyzer/debug build pass. Migration 20260906153952 deployed and verified
with rolled-back SQL assertions; existing inventory counts/quantities unchanged.
No device/manual tests or commit. Linked pgTAP is absent; transactional assertions
were used instead. See implementation notes for the verification detail.

## Shop-owned photos and main-screen polish

Separate verified shop Product photos from catalog moderation. Save photos to the
existing Product image URL through a service-only audited RPC; retain the legacy
global contribution endpoint. Support shop-only products and refresh photos
across receiving, details, inventory and expiry views. Simplify Home, scanner,
receiving, product list/details and profile without changing stock semantics.
Only focused tests/static checks; no app runs, device tests, full suite or commit.
