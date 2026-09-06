# Acceptance Criteria

## Production-safe product image contributions

- Resolved-product, manual-product, and receiving forms show a reusable image
  card with a robust remote placeholder/error state and the correct Add/Suggest
  action when a global CatalogProduct relationship exists.
- Camera and gallery selection support cancellation, permission denial, local
  removal, retry, duplicate-tap protection, and explicit selecting,
  processing, uploading, success, and recoverable-error states.
- Selected images are resized/compressed client-side, while the backend still
  enforces authoritative JPEG/PNG/WebP, byte-size, dimension, Cloudinary
  account/folder, and signed ownership context limits.
- Image failure never blocks Product saving or stock receiving. A recoverable
  failure keeps the local selection available for retry.
- Flutter contains no Cloudinary secret or Supabase service-role credential;
  widgets make no network/provider calls and use repository/adaptor boundaries.
- The backend derives the uploader from the verified JWT, verifies current Shop
  membership and an existing Product-to-CatalogProduct relationship, and writes
  only a pending non-canonical contribution from authoritative provider data.
- Authenticated clients cannot spoof uploader/shop/status/canonical state,
  invoke the trusted recording function, directly mutate canonical catalog
  images, contribute to unrelated CatalogProducts, or bypass MIME/size limits.
- Only `service_role` can approve/promote a valid contribution. RLS prevents
  users from reading or changing private contribution rows for shops they can
  no longer access.
- Focused Dart/widget, Edge Function, and pgTAP tests cover success, cancel,
  denied permission, invalid type/size, upload/verification failure, retry,
  duplicate taps, cross-shop/product attacks, canonical immutability, and ACLs.
- Formatting, analyzer, focused/full Flutter tests, Edge/Deno tests, database
  tests/reset/lint/advisors, and a build pass or are reported with an exact
  environment caveat. Only relevant files are committed.

## Ansar catalog synchronization

- Import only checksum-valid global GTINs from `Ansar Gallery Qatar`; reject
  invalid, internal, weighted, composite, and retailer-only identifiers while
  preserving leading zeroes.
- Reuse an existing global mapping, never reassign it, and create at most one
  CatalogProduct per newly observed GTIN under concurrent retries.
- Fill only empty catalog fields and retain SKU, source URL, confidence, and
  observation timestamps as provenance. Never ingest prices, promotions,
  availability, expiry, Batches, inventory, or shop Products.
- Expose ingestion and verification only to `service_role`; expose only narrow
  safe-field lookup plus confirmation-time shop Product creation to signed-in
  users.
- Advance the durable checkpoint only after complete ingestion and verification;
  support an idempotent full reconcile.
- Run tests, crawl, workbook verification, synchronization, remote verification,
  and only then commit workbook/crawl/sync/log state in GitHub Actions.
- Pass Python, affected and full Flutter, all pgTAP, clean reset, schema lint,
  rollback, linked dry run, security/performance advisors, production backfill,
  representative lookup, and protected-count verification.

- The selling-price migration remains intended, locally verified, compatible
  with CatalogProduct resolution, and undeployed.
- Linked preflight records exact counts, RPC contracts/grants, constraints, RLS,
  conflicts, and migration history; any discrepancy stops implementation.
- Existing external/manual RPC argument signatures and ten-field return shape
  remain unchanged with no overloads.
- Barcode resolution serializes global identity before Shop identity, creates
  one global barcode mapping, and gives each Shop its own Product.
- Manual global records use `user_contributed`; manual shop records use
  `local_manual`; the legacy external RPC preserves `open_food_facts`.
- Existing NULL Product links attach lazily; conflicting non-NULL links fail
  without mutation; no existing inventory identity is rewritten.
- Anonymous/non-member calls and direct catalog/barcode/Product identity
  mutation fail; the internal helper is unavailable to clients.
- A clean migration reset, all pgTAP, database lint, focused Flutter tests,
  actual same-/cross-Shop concurrency, rollback, and linked dry run pass.
- No Cloudinary/Migration 2, deployment, storefront enablement, or commit occurs.

## Shopkeeper workflow

- Known scans go directly to receiving; global/unknown scans review metadata once.
- Lookup errors allow retry; back never restarts a camera underneath manual entry.
- Required price, validated expiry and explicit positive quantity stay enforced.
- Photo preview, camera/gallery, replacement/removal and retry remain available without blocking receiving.
- Success offers scan next and product details; cancelled next scan retains success.
- Pending saves cannot be abandoned or double-submitted; temporary overlays retain draft fields.
- Focused tests, formatting, analyzer and build are reported; no backend changes/deployment/commit.

## Focused receiving follow-up (supersedes mandatory quantity)

Blank quantity persists and reads as null/unknown, positive explicit values still validate, and exact null retries deduplicate. Price per selling unit and expiry remain mandatory. Unknown batches stay visible. No barcode-less action or Add stock heading on receiving. Scanner has the secondary barcode-less option. Available brand/pack/barcode and active-shop currency render. Photo UI distinguishes approved from pending, offers one Add/Change action and no withdrawal after upload. More details holds lot without counter. Save stock remains accessible above keyboard and blocks duplicate writes. Deploy only the reviewed migration after focused automated verification.

## Shop-owned photos (supersedes shop-photo review requirements)

- Verified uploads immediately update only the selected shop Product, including
  barcode-less products; catalog canonical images remain unchanged.
- Preview, replacement, retry and navigation retain image state; shop photo
  saving is independent of optional global contribution/moderation.
- Server verifies JWT, membership, exact Product and authoritative asset context;
  client cannot invoke trusted recording or alter catalog canonical images.
- Main screens retain primary actions and expiry/stock functions with less
  duplicate UI. Focused image/backend/widget tests and static checks only.
