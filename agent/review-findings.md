# Review Findings

## 2026-09-04 — Ansar catalog synchronization

- `MEDIUM` — the importer returned the entire synchronized ID list in CLI JSON,
  causing catalog-sized workflow logs. Fixed by retaining IDs only in the atomic
  checkpoint and omitting them from operational output.
- `LOW` — one affected presentation test expected the superseded lookup label.
  Fixed to assert the current shop-first state before the global catalog stage.
- No remaining blocker, high, medium, or low findings after fixes and reruns.

## Global Catalog compatibility Migration 1 — resolved

- **HIGH:** Initial privilege hardening made an existing pgTAP insert with an
  explicit Product ID fail. This was a test-only use of authority the production
  barcode-less client never requests. The test now exercises the actual default-ID
  insert contract; client access remains intentionally narrow.
- **MEDIUM:** The first concurrency test left fixture memberships behind and
  contaminated a later whole-suite invariant. Cleanup now removes its exact
  UUID namespace and orphan test catalog rows; the affected 29-assertion role
  suite passes immediately afterward.
- **LOW:** The helper initially relied solely on the advisory lock plus the
  global unique barcode constraint. It now also verifies that an `ON CONFLICT`
  outcome cannot silently retain a different CatalogProduct identity.
- No unresolved BLOCKER, HIGH, MEDIUM, or LOW finding remains. Public signatures
  and return shape, provenance, grants, RLS, lazy attachment, conflict atomicity,
  inventory IDs, concurrency, and rollback were reviewed against the task.


## B12 real expiry dashboard Home — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after focused
  widget coverage and complete B12 diff review.
- Review caught and fixed a compact-width overflow in the received-date fact;
  long item facts now wrap within the Batch card.
- Every count/category is read directly from B11, unknown expiry is distinct,
  errors omit internal text, and Shop switching replaces old data with loading
  before the new Shop result arrives.
- No repository/Supabase call, device-time read, risk arithmetic, database
  change, Batch-detail navigation, notification, B13, or B22 work was added.

## B11 Riverpod expiry-dashboard controller — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after focused
  concurrency tests and full diff review.
- The initial single-provider design briefly retained Shop A's previous value
  during a Shop B dependency reload. Review caught this with an explicit test;
  the final private Shop-keyed family design keeps each Shop's async lifecycle
  separate and the public provider switches synchronously with active Shop.
- Review confirmed current Shop is the only public Shop source, stale and older
  overlapping responses cannot replace current state, and successful receiving
  invalidates the active dashboard only after persistence succeeds.
- Buckets are immutable partitions of B10/B08 output. No threshold, local date,
  device clock, Supabase type, write, widget, navigation, notification, database,
  or B12 behavior was introduced.

## B10 expiry-dashboard repository mapping — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after full
  diff review and focused verification.
- Review confirmed that the typed snapshot retains B09's authoritative date,
  all dated rows use B08 classification, unknown expiry stays unclassified, and
  neither adapter reads local time or reproduces bucket thresholds.
- Supabase responses fail closed on cross-Shop identity, missing/malformed
  fields, inconsistent reference dates/day offsets, invalid quantity, and absent
  empty-snapshot metadata. Existing authorization/backend errors retain typed
  repository semantics.
- The required B09 empty-result correction is limited to its undeployed,
  verification-pending migration and adds one matching pgTAP assertion. B09
  remains pending database execution; B10 requires no database verification.
- Review confirmed no Riverpod, UI, notification, persistence, B11, deployment,
  or unrelated refactor was introduced.

## B09 server-time expiry-dashboard read RPC — open verification

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after static
  review. The security-definer function authorizes the exact requested Shop,
  filters every Batch join by that Shop, pins its search path, validates the
  timezone, and exposes only the dashboard read contract to `authenticated`.
- Review confirmed zero-quantity history is excluded, historical null expiry is
  preserved, and the signed offset is raw date arithmetic rather than a second
  implementation of B08's buckets. No mutation or client/dashboard layer was
  added.
- **BLOCKER (verification environment):** migration execution, the 27-assertion
  pgTAP suite, database lint, and indexed-query `EXPLAIN` cannot run without the
  missing Docker/PostgreSQL/Supabase runtime. B09 remains verification-pending.

## B08 deterministic expiry-risk classification — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW finding remains after diff review and focused
  verification.
- The five categories are mutually exclusive and exhaustive for non-null
  `LocalDate` expiry values. Inclusive boundaries match the release plan, and
  month/year/leap transitions use date-only UTC-midnight arithmetic rather than
  elapsed local hours.
- Review confirmed that B08 adds no clock, timezone lookup, Riverpod/controller,
  widget, Supabase, RPC, migration, notification, or Batch-persistence behavior.
- B01–B06 implementation remains intact and B07 remains deferred.

## B06 owner-only member-role RPC — open verification

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after static
  review. Inputs and columns are explicitly qualified; the function locks and
  updates only the requested composite-key membership after owner authorization.
- Direct client membership mutation remains denied. The RPC cannot transfer
  ownership, promote an owner, demote an owner, move a membership, create a row,
  or change invite/join behavior. B05's owner-only Shop policy is unchanged.
- **BLOCKER (verification environment):** the migration, 29-assertion pgTAP
  suite, grant inspection, and local database reset/lint cannot execute without
  the missing local Supabase/PostgreSQL runtime. B06 remains verification-pending.

## B05 owner-only private Shop settings updates — open verification

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after static
  review. The corrective migration changes only the named Shop UPDATE policy;
  the authenticated table grant remains constrained by owner-only RLS.
- Member SELECT, Product, barcode, inventory, receiving, invitation, membership,
  and storefront policies are untouched. No client settings-edit path exists,
  so adding or hiding Flutter controls would exceed B05.
- **BLOCKER (verification environment):** the migration, focused 10-assertion
  pgTAP suite, and local database lint/reset cannot execute without the missing
  local Supabase/PostgreSQL runtime. B05 remains verification-pending.

## B04 barcode-less Product creation in receiving — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW implementation finding remains after the
  initial focused-test adjustment.
- The extra receiving action increased the form height; the existing retry
  widget regression test now scrolls the action into view before tapping it.
  Production behavior remains the same scrollable form.
- Review confirmed stale-shop results cannot enter receiving state, no widget
  calls Supabase, and no database or prior-blocker implementation was altered.

## B03 barcode-less Product repository support — open verification

- No implementation finding is currently recorded; final diff review and
  verification are pending.
- **BLOCKER (verification environment):** the expanded 24-assertion catalog RLS
  suite requires the unavailable local Supabase/PostgreSQL runtime. No database
  pass is claimed and deployment is not an acceptable substitute.

## B02 mandatory manual-receive expiry — open verification

- No BLOCKER, HIGH, MEDIUM, or LOW code finding remains after the fixer pass.
- Review confirmed the new RPC definition differs from the existing atomic,
  idempotent function only by `create or replace` and the null-expiry validation.
- Review corrected pgTAP expectations so the historical null-expiry fixture is
  excluded from new-receive join/value assertions, and retained the original
  quantity-validation precedence.
- **BLOCKER (verification environment):** the migration and 31-assertion pgTAP
  suite have not executed because no local Docker/PostgreSQL runtime exists.
  B02 must remain incomplete until `supabase db reset && supabase test db`
  passes; linked deployment is not an acceptable substitute in this task.

## B01 static storefront release gate — resolved

- No BLOCKER, HIGH, MEDIUM, or LOW implementation findings remain after review.
- The static flag is parsed centrally, has a safe default, and introduces no new
  state-management or routing dependency.
- Disabled mode has no public Explore root, browse tile, or management tile;
  the storefront providers remain lazy and no storefront repository call occurs.
- Explicit enablement retains the existing Explore → Shop Operations path and
  owner/manager management path. Storefront code and migration remain intact.
- Private Product, Batch, InventoryMovement, receiving, and RLS semantics were
  not changed.

## 2026-09-01 Android pilot audit — open

- **BLOCKER:** The expiry-loss workflow ends after receiving. Home contains
  hard-coded counts/products, `ExpiryRiskService` has no implementation, and no
  expiry dashboard data/controller exists.
- **BLOCKER:** No Batch-resolution mutation or history UI exists. Quantity
  cannot change after receiving even though movement types are modeled.
- **BLOCKER:** Notifications are only an unused port; there is no adapter,
  coordinator, permission flow, or Alerts screen.
- **BLOCKER:** New receiving accepts null expiry in domain, Flutter, and RPC,
  contrary to the explicit pilot batch requirement.
- **BLOCKER:** The app cannot create a Product without a barcode and cannot
  correct shop-local Product metadata after external/manual creation.
- **BLOCKER:** Android release identity/signing is template/debug: the package is
  `com.example.product_expiry_management`, label is the template name, and the
  built AAB certificate is `CN=Android Debug`.
- **BLOCKER:** Production defines can default to development because the current
  example/build contract omits `APP_ENV`.
- **HIGH:** The private Shop UPDATE policy authorizes every member, including
  workers. The pilot plan replaces it with owner-only authorization.
- **HIGH:** `manager` exists in schema/domain but no owner RPC/UI can assign it.
- **HIGH:** Client root always enters the optional public storefront while its
  schema migration is pending remotely. The plan gates this optional surface.
- **MEDIUM:** `shop_memberships_user_id_key` and membership RPCs enforce one Shop
  per user while the durable target/client selection model supports many.
- **MEDIUM:** Crash reporting is absent despite centralized error hooks.
- **LOW:** Android builds warn that `mobile_scanner` applies legacy KGP and that
  current compatibility flags are deprecated for Gradle 10. The clean release
  build passes, so modernization is post-release.
- **LOW:** Stale roadmap/README statements and untracked scratch/desktop template
  files obscure the release state. Documentation was reconciled; user-owned
  files were preserved.

## 2026-09-01 Android pilot audit — resolved in planning pass

- The complete evidence-backed release plan now exists at `docs/release-plan.md`.
- Architecture/roadmap/README text no longer describes Drift or initial receiving
  as the current implementation.
- Release blockers, important pilot gaps, deliberate deferrals, verification,
  and human-only decisions are explicit and independently executable.

## Customer storefront foundation — resolved

- **HIGH:** Using the same base-table SELECT path for customer and management
  reads meant an authenticated owner/manager could see draft listings and
  inactive/future deals in Explore because their management RLS policy is
  intentionally broader. Added unconditional security-invoker
  `public_storefront_*` views and moved public repositories to them; pgTAP and
  adapter tests cover the signed-in-manager customer projection.
- **MEDIUM:** The initial Set price action created a listing with
  `is_published=true` even when the user had not turned on the publication
  switch. New listing configuration now remains unpublished unless initiated by
  the explicit publish switch.
- **MEDIUM:** Deal validation was `SECURITY DEFINER` and could run its listing
  lookup before an INSERT's RLS `WITH CHECK`, allowing an unauthorized
  authenticated caller to probe guessed listing IDs. The trigger now performs
  an owner/manager authorization check before its privileged lookup.
- **MEDIUM:** Listing-price updates did not initially take the same advisory
  lock as deal writes, leaving a concurrent price/deal race around the
  offer-below-normal invariant. Both paths now serialize on the same
  `(shop_id, listing_id)` key; deals also cannot be moved between listings.
- **LOW:** The first customer listing view exposed the opaque internal
  `product_id` even though the customer UI needs only the listing ID. The public
  projection and adapter now omit it; the same-shop Product relationship remains
  management-only.

## Customer storefront foundation — open

None found in the reviewed Flutter or migration source. Actual pgTAP execution
remains blocked by the unavailable local database runtime and is recorded as a
verification limitation, not a code finding.

## Scan Product production verification — resolved

- **MEDIUM:** Product lookup and manual-save controllers could publish a Product
  after the selected shop changed while the request was in flight. The database
  write remained correctly scoped to the original shop, but stale UI state
  could be shown under the new shop session. Both controllers now capture the
  request shop, discard stale results (including session loss), and have focused
  Riverpod regression coverage.
- **LOW:** The product scanner callback did not check widget mounting before its
  first Riverpod read. The scanner controller already suppressed duplicate
  callbacks and navigation, but a plugin callback delivered after disposal
  could access a dead widget ref. `_onDetect` now exits immediately when
  unmounted.

## Scan Product production verification — open

None.

## Scan Product completion — resolved

- **MEDIUM:** `ProductFoundExternally` initially labeled every persisted result
  as Open Food Facts. The atomic RPC can return an existing manually entered
  Product when another request wins the shop/barcode race, so that label could
  misstate persisted provenance. The UI now derives the label from the returned
  Product source, with widget regression coverage.

## Scan Product completion — open

None.

## Resolved

- **LOW:** `API_BASE_URL` accepted URI schemes unsuitable for API calls. Fixed by
  requiring an absolute HTTP(S) URI with authority and adding a regression test.
- **LOW:** `ExpiryRiskService` was described but not represented in the initial
  domain contracts. Added the provider-independent contract and categories;
  deterministic implementation remains correctly deferred to Phase 2.

## Open

None.

## Phase 1 — Vertical Slice 1 resolved

- **MEDIUM:** Home still described manual receiving as future work. Updated it
  to direct users to the now-available Inventory flow.
- **MEDIUM:** An idempotency conflict had no explicit recovery action. Added a
  `Start new request` action that deliberately generates a fresh key while
  preserving reviewed form data, with widget coverage.
- **LOW:** The pending indicator could lack contrast inside a filled button.
  Added an explicit contrasting indicator color.
- **HIGH:** Android verification failed after the installed toolchain advanced
  to Flutter 3.47.2/Java 25 while the scaffold remained on Gradle 8.14. Aligned
  the project with the installed Flutter template (Gradle 9.3.1, AGP 9.1.0,
  Kotlin plugin 2.4.0, and current compiler DSL); the APK build now passes.

## Phase 1 — Vertical Slice 1 open

None.

## Authenticated barcode resolution — resolved

- **HIGH:** Production composition reused seeded `shop-demo` inventory after a
  real authenticated shop was selected. Replaced it with an empty in-memory
  receiving adapter until that adapter becomes shop-aware and Supabase-backed.
- **HIGH:** The existing dashboard header hardcoded `Green Mart`, which could
  misrepresent the active tenant. It now renders the explicitly selected shop.
- **MEDIUM:** Auth token refresh events could clear/reload the active shop and
  duplicate membership queries. The gate now tracks user/load generations,
  ignores same-user refreshes, and discards stale asynchronous results.
- **LOW:** The pgTAP plan declared 16 assertions while the suite contained 18.
  Corrected the plan count.

## Authenticated barcode resolution — open

None. The policy suite still requires execution on a machine with a local
Supabase-compatible PostgreSQL/container runtime; this is a verification
environment limitation rather than an unresolved code finding.

## Authenticated stock receiving — resolved

- **HIGH:** Receiving initially reused the local timestamp/sequence ID helper
  for idempotency keys. That is process-local and not a sufficient cross-device
  collision boundary. Replaced receiving keys with dependency-free,
  cryptographically secure UUID v4 values and added format/uniqueness coverage.
- **MEDIUM:** Initial RPC mapping verified internal Batch/Movement consistency
  but did not compare every returned ownership/payload field with the submitted
  request. Added strict shop, Product, quantity, nullable expiry/lot,
  idempotency-key, Batch/Movement consistency checks; malformed/mismatched
  responses now map to a controlled unavailable result.
- **MEDIUM:** Direct-mutation security tests covered inserts but not mutation of
  existing receiving history. Added explicit authenticated update/delete denial
  assertions; receiving tables expose member-scoped reads only.

## Authenticated stock receiving — open

None in the reviewed implementation. The new PostgreSQL/RLS suite could not be
executed because the local Supabase database is unavailable; this remains a
verification-environment blocker, not a reason to weaken the migration tests.

## Riverpod migration — resolved

- **HIGH:** A naive auth stream would rebuild the shop session for routine
  same-user token refresh events, briefly clearing the active shop and repeating
  membership queries. The auth identity provider now emits only when the user
  ID changes, with a regression test proving the selected shop remains stable.
- **MEDIUM:** Riverpod 3 automatically retries failed async providers by
  default. Automatic retry would bypass the deliberate shop/receiving error and
  user-controlled retry states. Retry is disabled for these controllers; their
  existing explicit retry actions remain authoritative.
- **MEDIUM:** Initial page constructors still accepted repositories/use cases,
  which would create two competing dependency paths. Removed those constructor
  parameters and supplied all existing dependency instances once through root
  provider overrides.
- **LOW:** The first shell conversion still held navigation and sign-out errors
  in widget state. Both are now notifier-owned, leaving stateful consumers only
  for disposable Flutter controllers and form keys.

## Riverpod migration — open

None found in the reviewed client implementation. Database verification remains
subject to the previously reported missing local Supabase/PostgreSQL runtime;
this migration did not alter schema or policies.

## QR shop invitation repair — resolved

- **HIGH:** Enabling invitations updated every historical row to active, reviving
  rotated/revoked codes and making the rendered invite arbitrary. The repair
  deactivates all but one row, adds a partial unique index, and makes enable
  select only the newest valid unexpired invite (or rotate a replacement).
- **HIGH:** The join RPC reported expired-code rejection but invites had no
  expiry field. Added a persisted seven-day expiry, server-time validation, and
  expired-row regression coverage.
- **MEDIUM:** Active invite reads used unordered `limit(1)`, so owners could
  render an arbitrary QR when bad data contained multiple active rows. The
  database now prevents that state and the repository orders current reads
  deterministically while excluding expired invites.
- **MEDIUM:** Scanner progress/error/deduplication was widget-local and camera
  failures had no retry action. Moved scan workflow state to an auto-disposed
  Riverpod controller and added permission/init/malformed/retry UI plus duplicate
  callback tests.
- **MEDIUM:** The partial implementation had no proof that scanning did not
  submit automatically or that manual and scanned codes shared one operation.
  Widget tests now prove scan-only selection, explicit confirmation, and the
  common `requestToJoinShop` repository call.
- **LOW:** iOS had repeated camera usage keys nested in unrelated dictionaries,
  owner sharing used a deprecated API, and the membership path introduced
  analyzer warnings. The plist now has one root key, sharing uses `SharePlus`,
  and static analysis is clean.
- **MEDIUM:** The initial repository fix filtered invite expiry with the device
  clock, so clock skew could render an invite the server considered expired.
  Active-invite reads now use an owner-only server-time RPC.

## QR shop invitation repair — open

No client or migration findings remain after the fixer pass. The pgTAP invite
suite could not run because the configured local PostgreSQL endpoint refused the
connection; this is a verification-environment limitation, not an open code
finding.

## Shop profile RPC ambiguity correction — resolved

- **HIGH:** Both deployed owner authorization subqueries used unqualified
  `user_id` and `role` references inside PL/pgSQL functions whose
  `RETURNS TABLE` schemas define same-named output variables. The corrective
  migration qualifies all table columns and preserves both public contracts.

## Shop profile RPC ambiguity correction — open

No code findings remain. The correction is deployed and both affected RPCs,
the active-invite RPC, non-owner rejection, and the Team & Access QR rendering
path passed post-deployment verification. The CLI pgTAP wrapper remains
unavailable because Docker Desktop is not installed, but equivalent isolated
linked SQL checks executed successfully and left no test data behind.

## Product image contribution flow — resolved

- **BLOCKER:** The deployed client-callable RPC trusted asset ID, URL, version,
  and Shop/catalog values, while authenticated users also retained direct table
  INSERT/UPDATE/DELETE. The hardening migration revokes every mutation path,
  makes the old RPC non-executable, and permits only a service-only RPC fed by
  authoritative provider metadata after membership/Product-link checks.
- **HIGH:** Initial verification cleanup could delete a Cloudinary asset after
  PostgreSQL committed but its response was lost. The fixer now performs a
  service-role idempotency lookup and returns the committed contribution; it
  deletes only after a successful lookup proves no row exists and preserves the
  asset when database state is uncertain.
- **HIGH:** Provider format, bytes, dimensions, account, folder, and uploader
  ownership were not all authoritative. Signed upload context plus Admin API
  validation and database constraints now cover each boundary; cleanup occurs
  only after the authoritative context proves the current caller owns the asset.
- **MEDIUM:** The first UI placement increased lazy-list extent enough to defer
  existing compact-screen controls. Cards now follow the scan/manual primary
  action, and receiving opens the card from a same-row optional photo action;
  the unchanged receiving widget suite passes.
- **MEDIUM:** A transport failure after selection discarded actionable state.
  The controller now retains the processed selection across offline/upload/
  verification failures and blocks repeated taps until the active operation
  completes.

## Product image contribution flow — open

No code findings remain after the fixer pass. The reviewed hardening migration
and both JWT-protected Edge Functions are deployed; linked privilege checks and
function status verification passed.

## App-wide operational UI consistency pass — resolved

- **HIGH:** Home displayed a fabricated `May 2025` date beside real expiry data,
  which could cause an unsafe stock decision. The rebuilt row shows only
  authoritative status and quantity data.
- **MEDIUM:** Alerts navigation led to a placeholder and multiple Home actions
  were no-ops. Alerts now exposes expired/today queues and decorative actions
  were removed.
- **MEDIUM:** Inventory had no inventory list or search despite being a primary
  destination. It now renders the existing authorized active-batch snapshot and
  filters locally by product, brand, or lot.
- **MEDIUM:** The first large-text review found status-summary overflow on a
  320px viewport at 1.8x text scale. The summary and status chip now reflow, and
  a regression test passes.
- **LOW:** Scanner presentation imported `dart:io` only to suppress an animation
  in tests. The static, responsive frame removes that web-hostile dependency and
  avoids a constant animation.

## App-wide operational UI consistency pass — open

No blocking code findings remain. Device camera/permission behavior and visual
inspection on physical iOS/Android hardware remain manual release checks.

## Product details and catalog UX follow-up — resolved

- **HIGH:** Blank receiving quantity was temporarily converted to one, creating
  false inventory and an audit movement not asserted by the user. The UI now
  rejects blank quantity because every existing domain/database receiving
  boundary requires a positive known value; no backend behavior was changed.
- **MEDIUM:** Inventory omitted Products without positive active batches despite
  an existing authorized complete-product read. Combined catalog state now
  renders all Products and derives batch status only from real dashboard rows.
- **MEDIUM:** Home and Alerts rows terminated in batch-only list views. They now
  open one operational Product Details screen, as do Inventory rows and the
  receiving-success action.
- **MEDIUM:** Alerts summarized categories without identifying affected items.
  It now ranks and renders actionable rows with icon, text, date, quantity, and
  a details destination.
- **LOW:** Long status chips in trailing list slots were likely to compress names
  on narrow or large-text devices. Status now reflows beneath row metadata.

## Product details and catalog UX follow-up — open

Barcode lists and movement history are not exposed by the current Flutter
repository contracts. Physical camera, platform keyboard, TalkBack/VoiceOver,
and system-bar checks remain device verification work.

## 2026-09-06 — Shopkeeper scanning workflow review

Reviewed scanner/resolution/manual handoff, shared launcher, receiving state,
image selection/upload and affected tests against this task's acceptance criteria.

- HIGH, fixed: receiving family arguments were equal for separate routes for the
  same Product, allowing a nested receive action to reuse an earlier success.
  Arguments now use route identity.
- MEDIUM, fixed: receiving another batch after scanning a different Product could
  select the route's original Product. It now retains the current selection.
- MEDIUM, fixed: cancelled/failed photo replacement could discard the previous
  contribution state and offer a duplicate upload. Preserve the contribution and
  prevent its resubmission.
- MEDIUM, fixed: photo state was disposed when its sheet closed. The receiving
  page now observes it through overlays and receipt display; failed/in-flight
  uploads remain visible on success for recovery.
- No backend/schema/security changes required. No remaining confirmed blocker.

## Focused Receive Stock follow-up review

Reviewed nullable quantity through validation, request JSON, Batch/Movement mapping,
RPC persistence, null-safe idempotency and expiry reads. Existing known quantities
are untouched. Non-received movements still require signed known deltas. Function
signatures, membership checks, RLS and mutation grants are unchanged.

Fixed during verification: thumbnail placeholder text overflow; tests now inspect
actual TextField keyboard configuration and use logical keyboard height. Explicit
null response fields are distinguished from missing contract fields. Pending
contributions cannot be removed through the UI/controller. No remaining blocker.

Local verification before deployment: 116 focused Flutter tests and 77 focused
pgTAP assertions pass; analyzer clean. Linked preflight has seven batches and seven
movements, all known, each quantity sum 106. No unrelated migrations are included.
