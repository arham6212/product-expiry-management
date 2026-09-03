# Implementation Notes

## 2026-09-03 — B06 owner-only member-role RPC

- Inspected the owner-only invite/review/profile RPCs, role constraint, direct
  membership grants/RLS, Team & Access Riverpod controller/screen, adapters,
  pgTAP style, and B05 policy. B07 explicitly owns Flutter integration, so no
  repository, controller, or widget API was added in B06.
- Added `update_shop_member_role(target_shop_id, target_user_id,
  requested_role)`, returning the persisted role text. It authenticates, accepts
  only exact manager/worker roles, authorizes the caller as same-shop owner,
  locks the exact target row, and rejects self/owner changes before updating the
  composite-key membership.
- Pinned the security-definer search path empty, fully qualified table aliases,
  revoked execute from public/anon/authenticated, then granted only
  authenticated. Direct membership mutation grants remain absent.
- Added a 29-assertion pgTAP suite covering grants, anonymous/manager/worker/
  cross-Shop denial, target-shop isolation, invalid roles, owner invariants,
  both allowed transitions, unchanged failures, roster visibility, invite
  preservation, membership identity/count, direct-update denial, and B05's
  manager Shop-update denial.
- Added a down script that removes the function. It deliberately does not guess
  historical roles; persisted changes require explicit audit/recovery.
- No prior migration, Flutter production code, invite/join behavior, ownership,
  deployment, commit, or B07 work changed.

### B06 verification

- `flutter test` — PASS (177 tests).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (100
  files, zero changes required).
- `flutter analyze` — PASS, no issues.
- `git diff --check` — PASS.
- `supabase status` — BLOCKED: it cannot connect to the Docker daemon at
  `/var/run/docker.sock`; `docker`, `podman`, `psql`, and `postgres` executables
  are unavailable. Therefore `supabase db reset && supabase test db` and local
  database lint were not run. No database PASS is claimed and nothing was
  deployed.

## 2026-09-02 — B05 owner-only private Shop settings updates

- Inspected the Shop UI, Riverpod session/member controllers, repository, table
  grants, RPCs, and RLS. There is no current private-settings screen, update
  controller, repository method, or Shop-update RPC; direct table UPDATE is the
  only lower-level path.
- Classified the private Shop row fields as tenant name, time zone, currency,
  and row identity/timestamps. Operational member reads require the same row but
  do not require mutation access. Public profile metadata is stored separately.
- Added additive migration `20260902000000_owner_only_shop_settings.sql`. It
  drops only `Members can update their shops` and replaces it with an owner-only
  policy using same-shop role checks in both `USING` and `WITH CHECK`.
- Added a focused 10-assertion pgTAP suite covering owner success; manager,
  worker, and cross-shop zero-row updates; anonymous grant denial; unchanged
  data after denials; and retained member reads.
- No Flutter, repository, RPC, Product, inventory, receiving, membership,
  storefront, or prior migration implementation changed. No deployment or
  commit was performed.

### B05 verification

- `flutter test test/features/shops test/features/auth/presentation/authenticated_shop_gate_test.dart test/features/inventory`
  — PASS (48 tests).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (100
  files, zero changes required).
- `flutter analyze` — PASS, no issues.
- `git diff --check` — PASS.
- `supabase status` — BLOCKED: it cannot connect to the Docker daemon at
  `/var/run/docker.sock`; `docker`, `podman`, `psql`, and `postgres` executables
  are unavailable. Therefore `supabase db reset && supabase test db` and
  `supabase db lint --local` were not run. No database PASS is claimed and
  nothing was deployed.

## 2026-09-02 — B04 barcode-less Product creation in receiving

- Added an auto-disposed family `Notifier` scoped by the receiving route's Shop
  ID. It captures the active Shop before creation, blocks parallel submissions,
  surfaces validation/backend errors for retry, and discards stale-shop results.
- Added a minimal name/optional-brand page that calls only the notifier. The
  notifier uses B03's Product repository boundary; widgets do not call Supabase.
- Receiving now offers “Add product without barcode” even with an empty Product
  list. The returned Product is inserted and selected in Riverpod receiving
  state while Flutter-owned quantity, expiry, and lot controllers retain their
  draft values.
- The final receive continues through the unchanged `ReceiveStock` use case and
  inventory repository/RPC boundary. No schema, migration, RPC, policy, package,
  storefront, barcode-resolution, or inventory semantic changed.
- Added focused notifier/page tests and a worker-level create-select-receive
  widget test, including validation, loading, backend failure, retry,
  double-submit, stale-shop, empty-list, draft-preservation, and success cases.

### B04 verification

- `flutter test test/features/inventory test/features/product_resolution` —
  PASS (105 tests).
- `flutter test test/app_shell_test.dart` — PASS (3 tests).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (100
  files, zero changes required).
- `flutter analyze` — PASS, no issues.
- `git diff --check` — PASS.
- Database/pgTAP execution was not run because B04 changes no database surface
  and its verification section does not require it. The known local
  Supabase/PostgreSQL runtime remains unavailable; no migration was deployed.

## 2026-09-01 — B03 barcode-less Product repository support

- Added one explicit `createManualProductWithoutBarcode` repository operation.
  It normalizes the Shop ID, required name, and optional brand before any write.
- The Supabase adapter inserts only `shop_id`, `name`, `brand`, and
  `source=local_manual` into `products`, then validates the returned ownership,
  metadata, provenance, and absence of image/source/global identity metadata.
- The in-memory adapter mirrors creation and validation while leaving barcode
  mappings untouched. It deliberately does not deduplicate names.
- Expanded repository tests for normalization, invalid input, exact Supabase
  payload, cross-shop/malformed identity responses, and zero barcode writes.
- Expanded the existing catalog pgTAP suite from 22 to 24 assertions to cover
  anonymous insert denial and the absence of a barcode child after a permitted
  same-shop direct Product insert. No migration was required or deployed.
- B02 and its corrective migration were not changed; B04 was not started.

### B03 verification

- Pending final command execution and results.

## 2026-09-01 — B02 mandatory expiry for new manual receiving

- Inspected both receive entry points: Inventory → Receive Stock and resolved
  Product → Receive Stock. Both converge on the same Riverpod controller,
  `ReceiveStock` use case, repository, and `receive_product_stock` RPC. Direct
  authenticated Batch/movement writes remain denied.
- `ReceiveStock` rejects missing expiry with field `expiryDate` before generating
  an idempotency key or repository request. `ReceivingRequest.expiryDate` is now
  non-nullable, while the persisted `Batch` remains nullable for history.
- The form labels expiry as required and distinguishes missing input from an
  invalid `YYYY-MM-DD` date. Validation writes nothing and preserves the draft.
- Added `20260901050000_require_manual_receive_expiry.sql`, replacing only the
  existing RPC definition with one null check before the unchanged lock/write
  transaction. The table column is untouched and historical null rows are not
  backfilled.
- Expanded pgTAP to 31 assertions covering null rejection with no Batch or
  movement, column nullability, historical-row readability, and existing
  authorization/quantity/idempotency/atomic behavior.
- Updated ADR-025 and current receiving behavior documentation. No B03 work,
  dependency, deployment, or commit was performed.

### B02 verification

- `flutter test test/features/inventory` — PASS (38 tests).
- `flutter test test/app_shell_test.dart test/domain/domain_models_test.dart` —
  PASS (10 tests).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (96 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- `git diff --check` — PASS.
- `supabase start && supabase db reset && supabase test db` — BLOCKED before
  migration execution: no Docker daemon is available, and this host has no
  Docker Desktop, Podman, `psql`, or local PostgreSQL runtime. No pgTAP pass is
  claimed and nothing was deployed.

## 2026-09-01 — B01 static storefront release gate

- Added strict compile-time parsing for `ENABLE_STOREFRONT`; omitted values
  default to `false`, and values other than `true`/`false` fail configuration.
- Selected Explore or authenticated Shop Operations at the composition root.
  Disabled mode also omits public-browse and storefront-management navigation,
  preventing the pending storefront schema from being queried through the app.
- Preserved all storefront repositories, providers, screens, tests, and the
  pending `20260901040000_public_storefront.sql` migration unchanged.
- Updated only documented release behavior and the example define. No
  dependency, inventory semantic, database state, commit, or deployment changed.

### B01 verification

- `flutter test test/core/app_environment_test.dart test/widget_test.dart test/app_shell_test.dart`
  — PASS (16 tests).
- `flutter test test/features/storefront test/features/auth/presentation/authenticated_shop_gate_test.dart`
  — PASS (18 tests).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (96 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- `git diff --check` — PASS.

## 2026-09-01 — Android pilot repository audit and release plan

- Inspected the complete Flutter feature tree, current domain/application/data
  boundaries, migrations/RPC/RLS declarations, pgTAP and Flutter test inventory,
  linked migration history, dependency state, and Android release configuration.
- Created `docs/release-plan.md` with 27 RELEASE BLOCKER, 4 IMPORTANT BEFORE
  PILOT, and 10 POST-RELEASE tasks. The tasks intentionally decompose database,
  repository, Riverpod, UI, notification, Android, and release operations.
- Corrected stale documentation: V1 is online-first, stock receiving is already
  persisted, and the audited release plan is the current execution source.
- Did not modify application code, migrations, dependencies, or production state.
- Preserved the dirty worktree and all untracked files.

### Audit verification

- `git status --short --branch` — PASS for inspection; worktree is heavily dirty
  with existing user changes and untracked implementation/platform files.
- `git diff --check` — PASS before this documentation pass.
- `dart format --output=none --set-exit-if-changed lib test` — PASS, 96 files,
  zero changes.
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 159 tests.
- `flutter build web --dart-define-from-file=config/env.example.json` — PASS.
- First `flutter build appbundle --release ...` — interrupted after a stale
  three-day Gradle/Kotlin daemon produced an incremental-cache assertion.
- `./gradlew --stop` plus `./gradlew clean` with the configured JDK — PASS.
- Clean retry `flutter build appbundle --release ...` — PASS, 64.2 MB AAB.
- AAB signer inspection — FAIL for production readiness: `CN=Android Debug`.
- `flutter pub outdated --no-dev-dependencies` — PASS; direct dependencies are current.
- `flutter doctor -v` — PARTIAL: Android license status unknown and an offline
  emulator; Flutter/Android SDK/network otherwise detected.
- `supabase migration list --linked` — PASS; remote is through
  `20260901030000`, with only `20260901040000` pending.
- `supabase db push --linked --dry-run` — PASS; would push only the storefront migration.
- `supabase status` / local pgTAP — BLOCKED because Docker/local PostgreSQL at
  `127.0.0.1:54322` is unavailable. No pgTAP pass is claimed.

## Phase 0

- Retained the existing Flutter toolchain.
- Added no provider or architecture dependency; retained Flutter's scaffolded
  Cupertino icon-font package because Flutter web's framework icon scan expects
  the font even though the current Material shell does not directly use it.
- Kept domain types independent from Flutter.
- Added a deterministic `ExpiryRiskService` contract without implementing the
  Phase 2 classification rules.
- Flutter's Android migrator added explicit compatibility flags for the current
  Gradle behavior during the first verified Android build.

## Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (19 files).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 17 tests.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` — PASS.

Phase 0 initially verified against Gradle 8.14, Android Gradle Plugin 8.11.1,
and Kotlin 2.2.20. During Phase 1 verification the installed Flutter/Android
Studio toolchain advanced to Flutter 3.47.2 and Java 25, so the project was
aligned to that Flutter release's current Android template: Gradle 9.3.1, AGP
9.1.0, Kotlin plugin 2.4.0, and the `compilerOptions` DSL.

## Phase 1 — Vertical Slice 1

- Added `ReceiveExistingProduct` with product lookup, identifier and quantity
  validation, deterministic entity construction, and typed failures.
- Added `InventoryRepository.commitReceiving` as the explicit atomic and
  idempotent persistence boundary.
- Added an in-memory adapter that publishes batch, movement, and idempotency
  receipt only after all staged work succeeds.
- Exact retries return the original records; conflicting key reuse is rejected.
- Added seeded existing products solely to exercise the temporary in-memory UI.
- Added Inventory → Receive Stock UI with loading, validation, pending, failure,
  success, and receive-another states.
- No external dependencies or provider SDKs were introduced.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (27 files).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 35 tests.
- `git diff --check` — PASS.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` — PASS.

## Authenticated shop catalog and barcode resolution

- Added one additive Supabase migration for shops, user memberships, products,
  and product barcodes. All exposed tables enable RLS, revoke `anon`, and scope
  authenticated operations through `auth.uid()` membership.
- Added `create_shop_with_owner` for the otherwise circular first-shop setup and
  `create_product_for_barcode` for atomic/race-safe external caching. Both are
  narrowly granted; no service-role credential is used by Flutter.
- Added explicit `CurrentShopContext`, email/password auth UI, automatic
  single-shop selection, multi-shop selection, and first-shop creation.
- Added `NormalizedBarcode` for 8/12/13/14-digit retail codes. It trims only
  surrounding whitespace and preserves leading zeroes/digit identity.
- Added `ResolveProductByBarcode`: current-shop database lookup always precedes
  external lookup. Outcomes distinguish local, external, not found, invalid,
  database/provider/persistence unavailable, and observable lookup stages.
- Added the Open Food Facts v3.6 product-by-barcode adapter with a limited field
  list, eight-second timeout, identifying native User-Agent, and typed
  response/error mapping. Browsers control their own User-Agent. Normal tests
  use mocked HTTP and never call the live API.
- Added `http` as a direct dependency because the SDK's transitive dependency is
  not a stable import contract and Dart/Flutter platform APIs do not provide one
  portable, mockable HTTP client across mobile and web.
- Added a temporary barcode-entry UI from the scanner action. It includes local
  and external loading states, found details, image placeholder, not-found,
  offline/error, retry, and a future-manual-add action.
- Kept Batch/expiry/movement behavior out of resolution. Production composition
  no longer exposes demo inventory across authenticated shops; the existing
  receiving adapter remains empty/in-memory pending its own persistence slice.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS.
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 91 tests.
- `git diff --check` — PASS.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS.
- `supabase test db --local supabase/tests/shop_catalog_rls.test.sql` — BLOCKED
  (connection refused): the local database at `127.0.0.1:54322` is unavailable
  and this machine has no
  Docker, Podman, PostgreSQL server, or `psql` executable. The pgTAP suite is
  included for execution in a Supabase-capable environment.

## Authenticated shop-owned stock receiving

- Added `batches` and `inventory_movements` as shop-owned Supabase tables with
  same-shop composite foreign keys, creator audit IDs, member-read RLS, no
  direct client mutation grants, and a reversible migration.
- Added `receive_product_stock` as the narrowly granted atomic write boundary.
  It authenticates, checks membership/Product ownership, validates quantity and
  optional lot input, serializes on shop/idempotency key, and creates one Batch
  plus one `RECEIVED` movement or returns the identical prior receipt.
- Kept movement history authoritative. `Batch.currentQuantity` is initialized
  in the same transaction as the received movement; Product has no stock total.
- Adapted the existing inventory repository boundary to require explicit
  `shopId`, accept nullable expiry/lot, and return typed application outcomes.
- Added `SupabaseInventoryRepository` with strict RPC request/response mapping
  and PostgreSQL/network failure categorization. Production composition now
  uses it; in-memory composition remains available for deterministic tests.
- Added a dependency-free secure UUID v4 generator for cross-device receiving
  idempotency keys. An unchanged UI retry reuses the key; editing the draft
  starts a new logical submission.
- Connected the resolved-Product Continue action to the receiving form with the
  Product preselected. The form validates quantity locally, keeps expiry/lot
  optional, blocks parallel taps, preserves values after failure, and confirms
  the durable receipt.
- Added application, in-memory transaction, Supabase response/error mapping,
  widget/navigation, domain, and pgTAP security/idempotency tests.

### Dependency decision

- No package was added. Secure idempotency identifiers use `Random.secure()`
  and RFC 4122 UUID v4 bit layout from the Dart SDK; the existing Supabase SDK
  remains the only database client.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (54 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 113 tests.
- `git diff --check` — PASS.
- `git check-ignore -v config/env.local.json` — PASS; ignored by
  `.gitignore:37`.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS.
- `supabase test db` — BLOCKED (exit 1): connection refused at the configured
  local PostgreSQL endpoint `127.0.0.1:54322`; no local Docker/Podman/PostgreSQL
  runtime is available. The 28-assertion receiving suite remains present and
  was not weakened or skipped silently.

## Riverpod state-management migration

- Added `flutter_riverpod ^3.4.2` as the single state-management dependency. No
  generator, hooks, Freezed, experimental persistence API, or second state
  package was added.
- Added one root `ProviderScope`. `AppDependencies` remains the composition
  object and supplies existing auth, shop, Product catalog/lookup, inventory,
  and receiving instances through provider overrides.
- Replaced mutable `CurrentShopContext` with an auth-driven
  `ShopSessionController`. It covers membership loading/retry, first-shop
  creation, automatic single-shop selection, explicit multi-shop selection,
  change-shop behavior, and identity reset. Same-user auth refresh events are
  filtered so token refresh does not clear or reload the current shop.
- Moved sign-in/up/out feedback, shell navigation, Product-resolution stages
  and results, and receiving Product load/submission/idempotent-retry state into
  Riverpod notifiers. Product resolution and receiving continue to scope every
  call with an explicit active `shopId`.
- Converted state consumers to `ConsumerWidget`/`ConsumerStatefulWidget`.
  Stateful consumers remain only where Flutter must dispose text controllers or
  own a form key; there are no workflow `setState` calls.
- Migrated widget tests to narrow `ProviderScope` overrides and added shop
  session tests for explicit selection, sign-out reset, and same-user refresh
  stability. Existing Product-resolution and receiving tests now exercise the
  Riverpod controllers through their widgets.
- No database migration, RLS policy, RPC, repository contract, domain rule, or
  Supabase adapter changed in this migration.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (59 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 115 tests.
- `git diff --check` — PASS.
- `git check-ignore -v config/env.local.json` — PASS; ignored by
  `.gitignore:37`.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS,
  including the WebAssembly dry run.
- `supabase test db` — BLOCKED (exit 1): connection refused at
  `127.0.0.1:54322`. This environment still has no running local Supabase
  PostgreSQL service; the existing database tests were not modified or skipped.

## QR shop invitation repair

- Investigated the partial owner QR, scanner, manual join, Riverpod, repository,
  navigation, migration/RLS/RPC, dependency, and platform configuration paths.
- Kept `ShopSessionController.requestToJoinShop(code)` as the only client join
  operation. Manual input and scanned input are normalized to the same code and
  reach that operation only after the user taps `Request to join`.
- Added `ShopInviteScanController` as an auto-disposed Riverpod state machine for
  accepted/invalid/retry and duplicate callback protection. The widget retains
  only `MobileScannerController` lifecycle and navigation responsibilities.
- Added actionable malformed-QR, camera permission, unsupported-camera,
  initialization, and retry UI without adding a second scanner or membership
  abstraction.
- Kept owner QR rendering driven by `ShopMembersController.activeInvite` and
  updated text sharing to the non-deprecated `SharePlus` API. No QR image is
  exported or claimed as shared.
- Added `expiresAt` to the invite domain record, an owner-only server-time active
  invite read, and an additive/reversible
  migration that backfills seven-day expiries, repairs multiple active rows,
  enforces one active invite per shop, serializes rotation/status changes, and
  validates active/unexpired codes under row locks.
- Cleaned the iOS camera usage description to one root key and declared Android
  camera/autofocus hardware as optional alongside the camera permission.
- Added pure Dart, Riverpod, widget-flow, owner QR refresh, domain expiry, and
  pgTAP regression coverage.

### Dependency decision

- Retained the already selected `qr_flutter ^4.1.0`, `mobile_scanner ^7.4.0`,
  and `share_plus ^13.3.0`. `flutter pub get` resolves them under Dart `^3.11.5`
  on Flutter 3.47.2 / Dart 3.13.2. Flutter has no platform-independent QR
  renderer, camera decoder, or native text-share API that covers this slice.

### Verification

- `flutter pub get` — PASS.
- `dart format --output=none --set-exit-if-changed lib test` — PASS (69 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- Focused QR/invite/domain/provider/widget tests — PASS (19 tests).
- `flutter test` — PASS (127 tests).
- `git diff --check` — PASS.
- `plutil -lint ios/Runner/Info.plist` — PASS; exactly one root camera usage key.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` —
  PASS. Flutter emitted a forward-looking warning that `mobile_scanner` still
  applies KGP internally; it did not affect the build.
- `flutter build ios --simulator --debug
  --dart-define-from-file=config/env.local.json` — PASS. Flutter aligned the
  project with its iOS 15 minimum and generated Swift Package Manager plugin
  integration, which is required by this Podfile-free current template.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS,
  including the WebAssembly dry run.
- `supabase test db` — BLOCKED (exit 1): the configured local PostgreSQL service
  at `127.0.0.1:54322` refused the connection. The new 19-assertion invite suite
  and existing suites remain present for a Supabase-capable environment.

## Shop profile RPC ambiguity correction

- Added the additive
  `20260901020000_fix_shop_profile_rpc_column_ambiguity.sql` migration; the
  deployed `20260831000000_multi_user_access.sql` file remains unchanged.
- Recreated `get_shop_members_with_users(uuid)` and
  `get_shop_pending_requests_with_users(uuid)` with their existing signatures,
  return schemas, PL/pgSQL/security configuration, owner-only authorization,
  result ordering, and authenticated grants.
- Qualified every table column in both function bodies. This removes the
  conflict between `RETURNS TABLE` output variables and membership columns such
  as `user_id` and `role` without changing business behavior.
- Added a focused four-assertion pgTAP suite covering authenticated-owner
  results from both RPCs and the unchanged authenticated non-owner rejection.
- No rollback file was added because reverting this function-only correction
  would deliberately restore the production defect; the prior definitions
  remain recoverable from the deployed migration if an emergency forensic
  reference is needed.
- No Flutter, Riverpod, navigation, QR, schema-table, policy, or unrelated RPC
  code changed in this slice.

### Verification

- `supabase db lint --linked --schema public --level warning --fail-on none` —
  CONFIRMED: the linked pre-correction definitions report SQLSTATE `42702` for
  both affected RPC owner checks.
- `supabase db push --dry-run --linked` — PASS: only
  `20260901020000_fix_shop_profile_rpc_column_ambiguity.sql` would be applied;
  nothing was deployed.
- New-file whitespace checks and the unqualified-column scan — PASS: unqualified
  conflict names occur only in `RETURNS TABLE` declarations, not function
  queries.
- `git diff --check` — PASS for tracked changes.
- `supabase test db --local supabase/tests/shop_member_profile_rpcs.test.sql` —
  BLOCKED: connection refused at `127.0.0.1:54322`; this environment has no
  local Supabase/PostgreSQL runtime. The subsequent linked verification section
  records the post-deployment execution fallback and results.

### Linked deployment and post-deployment verification

- `supabase db push --linked --yes` — PASS: applied only
  `20260901020000_fix_shop_profile_rpc_column_ambiguity.sql` and finished
  successfully.
- `supabase migration list --linked` — PASS: local and remote histories both
  include `20260901020000`.
- `supabase db push --dry-run --linked` — PASS: the remote database is up to
  date.
- `supabase db lint --linked --schema public --level error --fail-on error` —
  PASS: neither profile RPC reports SQLSTATE `42702`. A broader warning-level
  lint still reports the pre-existing `rotate_shop_invite_code` loop-variable
  warning, which is outside this correction.
- `supabase test db --linked supabase/tests/shop_member_profile_rpcs.test.sql` —
  BLOCKED before SQL execution because Supabase CLI requires Docker for its
  pgTAP runner and Docker Desktop is not installed.
- Used Supabase's linked management query workflow as the available staging
  fallback. One atomic verification transaction created isolated test rows,
  executed both RPCs as the real `authenticated` PostgreSQL role with an owner
  JWT claim, checked `get_active_shop_invite`, checked both non-owner failures,
  deleted every test row, and committed. All five checks passed. A subsequent
  read-only query confirmed zero test shops, memberships, requests, invites, or
  users remained.
- Focused Team & Access/controller widget tests — PASS (3 tests). Reaching the
  QR assertion proves the owner controller's three-operation `Future.wait`
  completed and supplied the active invite to `QrImageView`.
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 127 tests.
- No Flutter, Riverpod, repository, widget, migration, or pgTAP source was
  changed during deployment verification.

## Scan Product completion

- Preserved the existing `ResolveProductByBarcode` ordering: normalized
  barcode, selected-shop Supabase lookup, Open Food Facts only on a miss, then
  atomic persistence of a usable provider result.
- Verified the live Open Food Facts v3.6 product endpoint and official current
  API contract; no provider endpoint or response rewrite was required.
- Reused the installed `mobile_scanner` dependency for Product barcode camera
  capture. A small auto-disposed Riverpod controller owns accepted/invalid/retry
  state and duplicate callback suppression; typed barcode entry remains the
  camera/error fallback.
- Replaced the placeholder manual-add SnackBar with a validated manual Product
  form. Its Riverpod controller preserves form text on recoverable save errors
  and returns the persisted Product to the receiving navigation path.
- Added `create_manual_product_for_barcode` in additive migration
  `20260901030000`. It delegates to the deployed
  `create_product_for_barcode` RPC, so current-shop authorization, input
  normalization, advisory locking, mapping recheck, and the existing unique and
  same-shop constraints remain authoritative. Only a newly created row is
  changed to source `local_manual`; an existing concurrent winner is returned
  unchanged.
- Added strict client-side rejection if a Supabase lookup/save response claims
  a Product from a different shop.
- Added no dependency and made no Batch, expiry, movement, receiving, auth, or
  membership change.

### Verification

- Live Open Food Facts v3.6 known-product and not-found requests — PASS; the
  production response contract matches the adapter and no write request was
  made.
- Focused Product-resolution/domain tests — PASS (58 tests after review fix).
- `dart format --output=none --set-exit-if-changed lib test` — PASS (77 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS (138 tests).
- `git diff --check` — PASS.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS,
  including the WebAssembly dry run.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` —
  PASS. Flutter retained the existing forward-looking warning that
  `mobile_scanner` applies KGP internally; it did not affect the build.
- `supabase db push --dry-run --linked` — PASS; only
  `20260901030000_manual_product_for_barcode.sql` would be applied. Nothing was
  deployed.
- `supabase test db --local supabase/tests/shop_catalog_rls.test.sql` — BLOCKED
  before SQL execution because no local PostgreSQL/Supabase service is running
  at `127.0.0.1:54322`, and this environment has no Docker, Podman, or `psql`.

## Scan Product linked production verification

- Re-read the complete resolver, repository, Riverpod, scanner/manual UI,
  migration, pgTAP, domain, architecture, and task paths before deployment.
- `supabase db push --linked --yes` — PASS; applied only
  `20260901030000_manual_product_for_barcode.sql`.
- `supabase migration list --linked` — PASS; local and remote histories match
  exactly through `20260901030000`.
- `supabase db push --dry-run --linked` — PASS; remote database is up to date.
- `supabase db lint --linked --schema public --level error --fail-on error` —
  PASS. Warning-level lint still reports only the pre-existing
  `rotate_shop_invite_code` loop-variable warning.
- Created isolated authenticated owner/non-member users and shops through the
  linked APIs, then directly executed both Product-save RPCs. Fourteen checks
  passed: owner membership, external create/retry, manual create/retry, winner
  source preservation in both directions, same-shop mapping, cross-shop RLS,
  non-member and anonymous rejection, composite-FK rejection, and two truly
  concurrent external saves returning one Product/mapping winner.
- Deleted the isolated shops and auth users in a guaranteed cleanup path. A
  follow-up service-role read confirmed zero `codex-scan-*` users and zero
  verification shops remain.
- `supabase test db --linked supabase/tests/shop_catalog_rls.test.sql` — BLOCKED
  before pgTAP execution because the CLI requires Docker and no Docker daemon is
  available. No pgTAP success is claimed; the linked checks above are direct
  RPC/RLS integration verification, not a substitute label for pgTAP.
- The edge-case review found that lookup/manual controllers could surface an
  old-shop Product after the active shop changed mid-request. Both now capture
  the request shop and discard stale results, including session loss. The
  scanner callback now exits before reading Riverpod if its widget is unmounted.
- Added focused coverage for selected-shop change, session expiry, manual-save
  double submit, network-style manual-save failure with preserved fields and
  successful retry, and existing duplicate scanner callback suppression.

### Final verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (78 files,
  zero changes required).
- Focused Product-resolution/domain tests — PASS (62 tests).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS (142 tests).
- `git diff --check` — PASS.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS,
  including the WebAssembly dry run.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` —
  PASS. The existing forward-looking `mobile_scanner` KGP warning remains and
  does not affect the build.
- No offline catalog/outbox work and no commit were created.

## Customer storefront foundation

- Preserved `products` as the shop-owned identity used by barcode resolution,
  Batch, and InventoryMovement. Added an optional `catalog_product_id` link to a
  separate global CatalogProduct schema without backfilling or guessing matches.
- Added additive migration `20260901040000_public_storefront.sql` and rollback.
  It creates global catalog identity/barcodes, disabled-by-default public shop
  profiles, explicitly published Product listings, deals, filtered
  security-invoker customer views, role-aware RLS, same-shop foreign keys,
  integer-minor-unit price checks, server-time visibility, and serialized deal
  overlap/price validation.
- Public customer projections omit internal Product IDs and every Batch,
  expiry, stock, movement, supplier, cost, margin, member, and private Shop
  field. Anonymous users retain no inventory grants.
- Changed the application root to anonymous Explore. Shop Operations remains a
  separate route behind the existing auth/shop gate; signed-in staff can return
  to public browsing without changing the shop-session architecture.
- Added separate public and management repository/provider boundaries. Public
  providers accept explicit public shop IDs and have no active-shop dependency.
  Management providers require active shop and reject workers; PostgreSQL
  independently permits owners/managers only.
- Added Explore, storefront, searchable Product list, active Deals section,
  Product details, and explicit loading/empty/no-results/error/retry UI. Added
  owner/manager profile, publication/price, deal create/edit, and deactivation
  controls without gradients or another dependency.
- Review hardened the initial implementation: customer repositories now read
  unconditional public views so owner/manager SELECT policies cannot leak drafts
  into Explore; setting a price no longer implicitly publishes; the public view
  omits private Product IDs; deal triggers authorize before privileged lookup;
  and listing price/deal changes share one advisory-lock key.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (96 files,
  zero changes required).
- `flutter analyze` — PASS, no issues.
- Focused storefront/domain/data/provider/widget tests — PASS (14 tests).
- `flutter test` — PASS (159 tests), including existing barcode resolution,
  manual Product, auth/shop, invite, and stock-receiving regressions.
- `flutter build web --dart-define-from-file=config/env.local.json` — PASS;
  WebAssembly dry run also passed.
- `flutter build apk --debug --dart-define-from-file=config/env.local.json` —
  PASS. The pre-existing forward-looking `mobile_scanner` KGP warning remains.
- `git diff --check` — PASS.
- `supabase migration list --linked` — PASS: local/remote match through
  `20260901030000`; `20260901040000` is the only local-only migration.
- `supabase db push --dry-run --linked` — PASS: would push only
  `20260901040000`; nothing was deployed.
- `supabase db lint --linked --schema public --level error --fail-on error` —
  PASS for the currently deployed schema. It does not execute the pending
  migration.
- `supabase test db --local supabase/tests/public_storefront_rls.test.sql` —
  BLOCKED before SQL execution: connection refused at `127.0.0.1:54322`; no
  local PostgreSQL, Docker, Podman, or `psql` runtime is available. The new
  43-assertion suite remains unexecuted and no pgTAP pass is claimed.
- No migration deployment and no commit were created.
