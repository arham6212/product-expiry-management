# Android Pilot Release Plan

## Purpose and planning baseline

This plan is based on the repository and linked Supabase project inspected on
2026-09-01. It is an execution plan, not a claim that the listed work has been
implemented. Existing uncommitted work is user-owned and must be preserved.

The first controlled Android pilot succeeds when one real shop can complete this
path reliably:

`owner signs up -> creates a Shop -> optionally adds a worker -> scans a barcode or creates a barcode-less Product -> receives a dated Batch -> sees actionable expiry information -> confirms data is persisted and Shop-scoped`

Batch resolution, notifications, manager administration, Product correction,
and Play Store distribution remain valuable, but are not prerequisites for
this deliberately narrow receive-and-see-expiry pilot.

The customer storefront is preserved but is not on that critical path. Riverpod
remains the only Flutter workflow-state mechanism. The existing shop-owned
`products` identity remains the Product used by barcode, Batch, and movement
workflows.

## Repository assessment

### Architecture discovered

- Flutter 3.47.2/Dart 3.13.2 with Material 3 and one root Riverpod
  `ProviderScope`. There is no GoRouter dependency; navigation currently uses
  `MaterialPageRoute`, `Navigator`, and an `IndexedStack` shell.
- Presentation calls Riverpod application controllers; widgets do not call
  Supabase directly. Supabase adapters implement focused auth, shop, catalog,
  inventory, and storefront boundaries.
- Supabase Auth provides email/password identity. `shops` is the tenant and
  `shop_memberships` is the RLS authorization source.
- `products` and `product_barcodes` are shop-owned. Barcode resolution is
  database-first, then a race-safe manual barcode path. (Open Food Facts integration was retired).
- `batches` owns nullable expiry and cached quantity. `inventory_movements` is
  append-only audit history. `receive_product_stock` atomically creates one
  Batch and its initial `received` movement with idempotency protection.
- Owner-controlled invite codes/QRs, join requests, approval/rejection, and
  owner/manager/worker role values exist. The database still enforces one shop
  membership per user even though the Flutter session can select among several.
- A separate public storefront schema/client surface is implemented and
  privacy-oriented. Its migration `20260901040000_public_storefront.sql` is the
  only migration not present in the linked project.
- Configuration and global error hooks are centralized. There is no crash
  reporting adapter, notification adapter/coordinator, CI configuration, or
  production Android signing configuration.

### Release readiness by capability

| Capability | Assessment | Evidence |
| --- | --- | --- |
| Email/password auth | Complete for pilot basics | `auth_controller.dart`, `supabase_auth_service.dart`, auth widget tests |
| Shop creation/session | Complete for one-shop use | `shop_session_controller.dart`, `create_shop_with_owner` |
| Invite QR/code and owner review | Complete | invite migrations, `ShopMembersScreen`, pgTAP/widget tests |
| Roles | Partial | values and authorization exist; no owner workflow can promote a worker to manager |
| Multi-shop membership | Partial/blocked by schema | Flutter can select shops; `shop_memberships_user_id_key` and RPC checks enforce one |
| Barcode/manual entry | Complete | typed and camera input use one Riverpod resolution workflow |
| Database-first/external/manual lookup | Complete | focused repository/provider, atomic barcode RPCs, tests |
| Product without barcode | Missing creation path | receiving can select one if it exists, but the app cannot create one |
| Product correction | Missing UI/application path | table update policy exists, but no repository/controller/screen exposes correction |
| Batch receiving | Partial | atomic and retry-safe, but expiry is optional despite the release requirement |
| Multiple batches/received date | Complete | every receive creates a new Batch and server timestamps it |
| Expiry classifier/dashboard | Missing | only an abstract service and hard-coded demo Home values exist |
| Batch resolution/history | Missing | movement types exist, but no mutation RPC, repository workflow, or screen exists |
| Notifications | Missing | only an unused domain port exists; Alerts is a text placeholder |
| RLS/shop isolation | Strong foundation, one policy gap | pgTAP suites exist; all members can currently update private `shops` settings |
| Loading/error/retry | Good on implemented workflows | auth, shops, product resolution, receiving, and storefront cover main states |
| Android build | Builds, not releasable | AAB builds but uses `com.example...`, template label, and Android Debug signer |
| Production environment | Partial | centralized defines exist; example omits `APP_ENV`, so release builds default to development |
| Crash reporting | Missing | `AppLogger` and error hooks exist but have no remote sink |
| Automated verification | Partial | 159 Flutter tests pass; pgTAP exists; no CI and no running local database |

### Known obsolete, duplicated, and unnecessary work

- The numeric Home dashboard, supplier-return card, value-at-risk amount, and
  product rows are hard-coded demo data. They must be replaced, not connected to
  speculative supplier/POS/reporting features.
- `docs/roadmap.md` and the README contain stale phase statements; this file is
  now the release execution source of truth.
- Camera error widgets are duplicated between Product and invite scanners, but
  they work and should not be refactored before release merely for reuse.
- Untracked desktop template folders, `scratch/sample_app`, and `tmp.dart` are
  repository hygiene concerns. They are not Android runtime blockers and must
  not be deleted without confirming ownership.
- OCR, offline synchronization, POS, suppliers, advanced analytics, and expanded
  storefront/customer commerce are unnecessary for the core pilot.

## Execution rules for every task

Before each task, read `AGENTS.md`, `agent/current-task.md`, the task below, and
the referenced code/tests. Use the repository workflow:

`Planner -> Implementer -> Reviewer -> Fixer -> Verification -> Commit`

Do not commit unless the user separately authorizes it. Every migration must be
incremental and must assume production tables contain data. Run focused tests
before the standard verification commands. Never weaken RLS or replace the
shop-owned Product identity.

## Pilot-first classification and execution order

This classification supersedes the former assumption that every `B` task was a
blocker for the first real-shop trial. Counts below cover the 21 tasks from
`B07` through `B27`; B08 has since completed.

| Classification | Count | Ordered tasks |
| --- | ---: | --- |
| PILOT BLOCKER | 8 | B08, B09, B10, B11, B12, B22, B25, B26 |
| PLAY STORE BLOCKER | 11 | B07, B13, B14, B15, B18, B19, B20, B21, B23, B24, B27 |
| POST-PILOT | 2 | B16, B17 |

Each remaining B task was reviewed independently:

| Task | Classification | Pilot decision |
| --- | --- | --- |
| B07 — Add owner role controls to Team & Access | PLAY STORE BLOCKER | Approved users already become workers; one owner plus workers is sufficient for the pilot, so manager promotion/demotion is not on its core path. |
| B08 — Implement deterministic expiry-risk classification | PILOT BLOCKER | The pilot cannot present actionable expiry information without correct, shared bucket boundaries. |
| B09 — Add a server-time expiry-dashboard read RPC | PILOT BLOCKER | Trusted Shop-timezone calculations and same-Shop active-stock reads are required for safe real data. |
| B10 — Map expiry-dashboard data in InventoryRepository | PILOT BLOCKER | The dashboard needs a validated application boundary; presentation must not call Supabase directly. |
| B11 — Add the Riverpod expiry-dashboard controller | PILOT BLOCKER | Loading, bucketing, refresh, retry, and Shop-change safety are required before showing real expiry state. |
| B12 — Replace the demo Home with the real expiry dashboard | PILOT BLOCKER | Hard-coded demo values cannot guide a real shopkeeper; the received Batch must become practically visible. |
| B13 — Add an idempotent Batch-resolution RPC | PLAY STORE BLOCKER | Resolution is needed for a durable full inventory lifecycle, but the narrow pilot can validate receiving and observation before this workflow is introduced. |
| B14 — Add the Batch-resolution application boundary | PLAY STORE BLOCKER | It depends on deferred B13 and is not used by the receive-and-see-expiry pilot. |
| B15 — Add Batch detail, resolution, and history UI | PLAY STORE BLOCKER | It closes the later resolution workflow, but is outside the stated pilot journey. |
| B16 — Add shop-owned Product correction to the repository | POST-PILOT | Metadata correction is useful feedback-driven completeness, not a prerequisite for creating/resolving a Product and receiving stock. |
| B17 — Add minimal Product correction UI | POST-PILOT | It depends on deferred B16 and improves convenience rather than pilot safety. |
| B18 — Define a deterministic, low-noise notification policy | PLAY STORE BLOCKER | A supervised pilot can inspect the dashboard directly; notification behavior can wait for broader-release readiness. |
| B19 — Implement the local notification adapter and Android setup | PLAY STORE BLOCKER | Notification permissions/scheduling do not block installation or the core pilot workflow. |
| B20 — Add the notification reconciliation coordinator | PLAY STORE BLOCKER | It depends on deferred notification and resolution work and is not needed for direct dashboard use. |
| B21 — Replace Alerts placeholder with notification status and retry UI | PLAY STORE BLOCKER | The Alerts surface must be finished before a broad release, but it does not gate the controlled core-flow trial. |
| B22 — Add an explicit production environment build contract | PILOT BLOCKER | The installed app must fail closed on missing/wrong production Supabase values and keep storefront disabled. |
| B23 — Set the immutable Android application identity and branding | PLAY STORE BLOCKER | A controlled APK can be sideloaded with the temporary identity; immutable identity/branding must be settled before Play publication. |
| B24 — Configure non-debug Android release signing | PLAY STORE BLOCKER | Securely delivered controlled sideloading does not require the Play upload key; debug signing must still be eliminated before Play distribution. |
| B25 — Verify and deploy the complete migration chain | PILOT BLOCKER | Pending RPC/RLS behavior and the dashboard RPC must pass together before real shop data uses the linked backend. |
| B26 — Run the real-device critical-path smoke matrix | PILOT BLOCKER | This is the final proof that installation, auth, receive, dashboard, persistence, and Shop isolation work together. |
| B27 — Produce and hand off the closed-pilot Android release | PLAY STORE BLOCKER | Play closed-track packaging, metadata, signing, and handoff are unnecessary for the first controlled sideload. |

No Medium implementation slice remains before the release checkpoints. `B25`
completed the single database verification/deployment checkpoint for B02, B03,
B05, B06, and B09. `B26` is the next executable PILOT BLOCKER and the controlled
real-device acceptance pass.

The minimum dependency graph is:

- Dashboard: `B02 -> B09 -> B10`, plus completed `B08`; both branches join at
  `B11 -> B12`.
- Production-configured install: `B01 -> B22`.
- Database checkpoint: `B02 + B03 + B05 + B06 + B09 -> B25`.
- Pilot gate: `B04 + B12 + B22 + B25 -> B26 -> first real-shop pilot`.

The non-`B` items are not included in the counts above. `I01`, `I03`, and `I04`
are POST-PILOT for this controlled trial. `I02` is a PLAY STORE BLOCKER; the
pilot may use a pre-verified account and direct human support if credentials are
lost.

## P0 — Release correctness and access control

### B01 — Gate the optional storefront with a static release flag

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-01.

**Goal:** Production can open directly into Shop Operations while the existing
customer storefront remains available when explicitly enabled.

**Why this is needed:** The customer storefront is not a core-release blocker,
but the current root always queries storefront views that are absent from the
linked database. A lightweight compile-time flag removes that coupling without
deleting the completed storefront.

**Current implementation:** `AppEnvironment` strictly parses the static
`ENABLE_STOREFRONT` define and defaults it to `false`. Disabled builds start in
`AuthenticatedShopGate` and omit storefront browsing/management navigation;
explicitly enabled builds preserve Explore and Shop Operations. Migration
`20260901040000` is deployed, while the pilot build flag remains disabled.

**Scope:** Add `ENABLE_STOREFRONT` to `AppEnvironment`; default it to false for
production and true only when explicitly supplied. Select `ExploreShopsPage` or
`AuthenticatedShopGate` at the composition root. Add environment and root
widget tests and document the define.

**Out of scope:** Do not delete storefront code, change its schema, add remote
feature flags, or refactor navigation.

**Files/components to inspect:** `lib/core/config/app_environment.dart`,
`lib/app/expiry_management_app.dart`, `lib/features/storefront/presentation/`,
`test/core/app_environment_test.dart`, `test/widget_test.dart`, README,
`config/env.example.json`.

**Implementation steps:**

1. Parse one strict boolean compile-time value with a safe production default.
2. Choose the root surface in `ExpiryManagementApp` without introducing another
   state-management or routing dependency.
3. Test production default-off and explicit on/off behavior.
4. Document the define and keep Shop Operations reachable in both modes.

**Acceptance criteria:** A production configuration without the flag performs
no public-storefront query before auth; `ENABLE_STOREFRONT=true` preserves the
existing Explore flow; invalid values fail configuration clearly.

**Verification:** `flutter test test/core/app_environment_test.dart test/widget_test.dart test/app_shell_test.dart`; then `dart format --output=none --set-exit-if-changed lib test && flutter analyze`.

**Dependencies:** None.

**Risk notes:** Do not make a release build silently depend on a database surface
that is intentionally optional.

### B02 — Require expiry on every new manual receive

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-04. The full migration chain reset cleanly and
the 31-assertion stock-receiving pgTAP suite passed during B25.

**Goal:** New stock cannot be received without a validated expiry date.

**Why this is needed:** The stated V1 batch data requires Product, expiry, and
quantity. Today the domain use case, Flutter form, and RPC all accept null.

**Current implementation:** The worktree requires expiry in `ReceiveStock`, the
repository request, the form, and corrective `receive_product_stock` migration.
`Batch.expiryDate` and `batches.expiry_date` remain nullable for historical
records. Flutter tests and the local migration/pgTAP verification pass.

**Scope:** Keep the column/domain value nullable so existing unknown-expiry rows
remain readable, but reject null for new `receive_product_stock` calls and in
`ReceiveStock` validation. Make the form required and retain date-picker/manual
ISO validation. Update pgTAP, application, repository, controller, and widget
tests plus the receiving docs/ADR.

**Out of scope:** Do not backfill or delete existing null-expiry Batches, add OCR,
or add expiry correction in this task.

**Files/components to inspect:** `lib/features/inventory/application/receive_stock.dart`,
`receive_stock_controller.dart`, `receive_stock_page.dart`,
`supabase/migrations/20260830010000_stock_receiving.sql`, next migration,
`supabase/tests/stock_receiving_rls.test.sql`, receiving tests, domain docs.

**Implementation steps:**

1. Add a corrective migration that replaces the RPC and rejects null before any write.
2. Add use-case validation that returns a field-specific expiry error without generating a request.
3. Mark the form required and preserve entered values after recoverable failures.
4. Replace tests that endorse optional new receives with required-expiry tests.
5. Record why the table remains nullable for legacy safety.

**Acceptance criteria:** New client and direct RPC receives without expiry write
nothing; valid dated receives remain atomic/idempotent; existing null rows remain
readable and untouched.

**Verification:** `flutter test test/features/inventory`; `supabase start && supabase db reset && supabase test db`; standard Flutter checks.

**Dependencies:** B01 only for release ordering; implementation is otherwise independent.

**Risk notes:** Setting the table column `NOT NULL` without a verified backfill is forbidden.

### B03 — Add repository support for Products without barcodes

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-04. Flutter verification passes, the full
migration chain reset cleanly, and the 24-assertion Shop-catalog RLS/pgTAP suite
passed during B25.

**Goal:** Create a shop-owned manual Product without inventing a barcode.

**Why this is needed:** V1 explicitly supports Products without barcodes. The
existing manual path always requires and persists a barcode.

**Current implementation:** `ProductCatalogRepository` now includes a narrow
normalized manual Product insert with no barcode. Supabase and in-memory
adapters create only the shop-owned `local_manual` Product; focused Flutter
tests pass. `products` already allows same-shop member insert through RLS and
does not require a barcode child row. The expanded pgTAP suite passes locally.

**Scope:** Add a narrowly named repository operation for a normalized manual
Product without a barcode, implement Supabase and in-memory adapters, validate
the returned shop/Product, and add tests.

**Out of scope:** Do not create a fake barcode, global catalog record, supplier,
price, or automatic deduplication rule.

**Files/components to inspect:** `product_catalog_repository.dart`, Supabase and
in-memory catalog repositories, `domain_models.dart`, catalog migration/RLS,
repository tests.

**Implementation steps:**

1. Define input/output/failure semantics for one shop-owned Product insert.
2. Insert only customer-independent Product metadata with source `local_manual`.
3. Implement the same validation and deterministic test behavior in memory.
4. Test blank names, cross-shop/malformed responses, and zero barcode rows.

**Acceptance criteria:** A member can create a Product with no ProductBarcode;
anon/cross-shop access remains denied; no guessed global identity is created.

**Verification:** `flutter test test/features/product_resolution/data test/features/product_resolution/application`; `supabase test db` after adding focused RLS assertions if direct insert coverage is missing.

**Dependencies:** None.

### B04 — Expose barcode-less Product creation in receiving

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-02. A feature-scoped Riverpod notifier and
minimal name/optional-brand form create through the B03 repository boundary,
discard stale-shop results, and return the Product to the unchanged dated
receiving flow. Focused and feature regression tests plus standard Flutter
checks pass; no database change or verification is required by B04.

**Goal:** From receiving, a worker can add a named Product with no barcode and
continue directly to dated Batch entry.

**Why this is needed:** Repository support alone does not make the required
workflow usable.

**Current implementation:** `ReceiveStockPage` keeps its Product dropdown and
now exposes a barcode-less creation action even when the list is empty. The new
form is separate from barcode-bound `ManualProductEntryPage`, returns the saved
Product, selects it, and preserves the receiving draft.

**Scope:** Add a feature-scoped Riverpod create controller or safely generalize
the existing manual controller; add an “Add product without barcode” action;
return the persisted Product and select it in the existing receive form.

**Out of scope:** Do not add product images, supplier data, prices, bulk import,
or a general catalog administration module.

**Files/components to inspect:** manual Product application/presentation files,
`receive_stock_page.dart`, active-shop providers, relevant widget/controller tests.

**Implementation steps:**

1. Capture the active shop at submission start and discard stale cross-shop results.
2. Build a minimal required-name form with optional brand only.
3. Hand the saved Product back to receiving and keep existing draft fields.
4. Cover loading, validation, backend error, retry, double-submit, and success.

**Acceptance criteria:** The worker creates and receives a Product without a
barcode in one flow; all state is Riverpod-owned except disposable form controls.

**Verification:** focused controller/widget tests; `flutter test test/features/inventory test/features/product_resolution`; standard Flutter checks.

**Dependencies:** B03.

### B05 — Restrict private Shop settings updates to owners

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-04. The full migration chain reset cleanly, the
10-assertion Shop-settings RLS suite passed, and local database lint completed
during B25.

**Goal:** Workers and managers cannot mutate tenant identity/configuration through the API.

**Why this is needed:** The current `Members can update their shops` policy
authorizes every member even though sensitive administration is owner-only and
there is no reviewed settings workflow.

**Current implementation:** Corrective migration
`20260902000000_owner_only_shop_settings.sql` replaces only the Shop UPDATE
policy with same-shop owner checks in `USING` and `WITH CHECK`. Member SELECT and
all unrelated operational policies remain unchanged. No private-settings client
workflow currently exists. Static review and local database execution pass.

**Scope:** Add one corrective migration replacing only the Shop UPDATE policy
with an owner check. Add owner/manager/worker/cross-shop pgTAP cases.

**Out of scope:** Do not build a settings screen, change Product permissions, or
rewrite the membership model.

**Files/components to inspect:** shop catalog migration, `shop_catalog_rls.test.sql`,
`shop_memberships`, `is_shop_member`.

**Implementation steps:** Drop the named policy, create an owner-scoped policy,
preserve member SELECT, and test direct REST-role semantics.

**Acceptance criteria:** Owner same-shop update succeeds; manager, worker,
cross-shop member, and anon updates affect zero rows.

**Verification:** `supabase db reset && supabase test db`; `supabase db lint --local` if supported by the installed CLI.

**Dependencies:** None.

**Risk notes:** This deliberately chooses owner-only until a specific manager
settings permission is approved.

### B06 — Add an owner-only member-role RPC

**Priority:** RELEASE BLOCKER

**Status:** Complete on 2026-09-04. The full migration chain reset cleanly and
the 29-assertion role-RPC pgTAP suite passed during B25.

**Goal:** An owner can promote/demote a member between manager and worker safely.

**Why this is needed:** The database recognizes `manager`, but approved users
always become workers and no supported operation can assign the manager role.

**Current implementation:** `review_join_request` still creates `worker` and
membership rows remain directly immutable to clients. The versioned
`update_shop_member_role` function now lets only a same-shop owner lock and
toggle a non-owner target between `manager` and `worker`; its grant, role,
ownership, tenant, and unchanged-data assertions pass under local pgTAP.

**Scope:** Add one security-definer RPC that locks the target membership,
authorizes the caller as same-shop owner, accepts only manager/worker, and
prevents self-demotion/owner-role changes. Add pgTAP coverage and recovery notes.

**Out of scope:** Do not add ownership transfer, member removal, custom roles,
or broaden manager administration.

**Files/components to inspect:** multi-user migration, member profile RPCs,
`shop_member_profile_rpcs.test.sql`, `shop_memberships` constraints.

**Implementation steps:** Define strict inputs/errors, pin `search_path`, revoke
default execute, grant only authenticated, serialize the target row, test all roles.

**Acceptance criteria:** Same-shop owner can toggle worker/manager; every other
caller and every attempt to alter an owner is rejected without a write.

**Verification:** `supabase db reset && supabase test db`; inspect grants with the pgTAP suite.

**Dependencies:** B05 is recommended first so administrative rules stay conservative.

### B07 — Add owner role controls to Team & Access

**Priority:** PLAY STORE BLOCKER

**Goal:** Owners can use the role RPC from the existing member list with clear feedback.

**Why this is needed:** V1 roles must be operational, not schema-only.

**Current implementation:** `ShopRepository` lists member profiles;
`ShopMembersController` handles invite/review actions; `ShopMembersScreen` shows
read-only role chips.

**Scope:** Add the repository method, Supabase/in-memory implementations,
controller action state, and owner-only manager/worker control. Refresh the
roster after success and preserve errors for retry.

**Out of scope:** Do not change invite approval, transfer ownership, or allow managers to administer members.

**Files/components to inspect:** `shop_access.dart`, shop repositories,
`shop_members_controller.dart`, `shop_members_screen.dart`, related tests.

**Implementation steps:** Map typed roles to RPC strings, block duplicate taps,
render controls only for non-owner rows when current user is owner, and test role visibility/authorization errors.

**Acceptance criteria:** Owner promotion/demotion is visible after success;
manager/worker see no controls; failure leaves the prior roster intact and retryable.

**Verification:** `flutter test test/features/shops`; standard Flutter checks.

**Dependencies:** B06.

## P1 — Core expiry vertical slice

### B08 — Implement deterministic expiry-risk classification

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-03.

**Goal:** Classify a date into Expired, Today, Next 7 days, 8–30 days, or Later.

**Why this is needed:** Dashboard and notification code must share tested rules;
the existing service is abstract and its enum does not exactly match the release buckets.

**Current implementation:** `CalendarExpiryRiskService` implements the existing
provider-independent contract over explicit `LocalDate` inputs. It classifies
signed calendar-day offsets as expired (`<0`), expires today (`0`), next 7 days
(`1..7`), 8–30 days (`8..30`), or later (`31+`). Both inputs are converted to
UTC midnight only for calendar-day counting; no clock, timezone lookup, Flutter,
Supabase, locale, or UI dependency is present. Unknown expiry remains a separate
caller-owned state.

**Scope:** Define exact inclusive boundaries and implement a pure Dart service.
Unknown expiry is handled by callers as a separate “Needs date” state.

**Out of scope:** Do not read device clocks/timezones, schedule notifications,
or implement FEFO in this task.

**Files/components to inspect:** `expiry_risk_service.dart`, `local_date.dart`,
domain model/tests, product spec.

**Implementation steps:** Align the enum, implement date-difference rules, and
test month/year/leap boundaries plus dates at -1, 0, 1, 7, 8, 30, and 31 days.

**Acceptance criteria:** Classification is deterministic and contains no Flutter,
Supabase, locale, or current-clock dependency.

**Verification:** `flutter test test/domain`; `flutter analyze`.

Focused B08 tests and the combined domain/inventory regression suite pass,
including -1/0/1/7/8/30/31-day boundaries, month/year rollover, leap day, and
repeat determinism. Formatting, analysis, and `git diff --check` also pass. No
database verification is required because B08 changes no database surface.

**Dependencies:** None.

### B09 — Add a server-time expiry-dashboard read RPC

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-04. The full migration chain reset cleanly, the
27-assertion dashboard pgTAP suite passed, local lint completed, and a
representative `EXPLAIN` used `batches_shop_expiry_idx` during B25.

**Goal:** Return active Batch rows with Product display data and server-derived
days-to-expiry in the Shop timezone.

**Why this is needed:** The dashboard must not use hard-coded data or silently
trust an incorrect device clock. Existing indexes support the query, but no
read contract joins the required fields.

**Current implementation:** Additive migration
`20260903110406_expiry_dashboard_read_rpc.sql` defines the stable,
security-definer `get_expiry_dashboard(uuid)` read contract. It authenticates
and independently authorizes exact Shop membership, validates the stored IANA
timezone, derives `reference_date` from PostgreSQL `now()`, and returns only
positive-quantity same-Shop Batch/Product display rows. An empty Shop returns a
metadata-only row so the authoritative reference date remains available. Raw
nullable expiry and nullable signed offset are preserved; no B08 bucket
threshold is duplicated. Static review, Flutter regressions, and database
execution pass.

**Scope:** Add one read-only, member-authorized function returning Batch ID,
Product display fields, expiry, quantity, received timestamp, and signed day
offset based on PostgreSQL `now()` in `shops.time_zone`. Include positive-quantity
item rows and unknown-expiry rows; exclude zero-quantity history, and preserve
reference-date metadata when no item rows exist.

**Out of scope:** Do not expose movements, cost, exact data publicly, mutate
Batches, or add materialized caches.

**Files/components to inspect:** shops/batches migrations, next migration,
`stock_receiving_rls.test.sql`, indexes and timezone constraints.

**Implementation steps:** Authorize with membership, validate stored timezone,
pin search path, order urgent first, revoke public execute, grant authenticated,
and test cross-shop/anon/unknown/boundary cases.

**Acceptance criteria:** Results use database time and shop timezone; only
same-shop active stock is returned; no customer/anon grant is added.

**Verification:** `supabase db reset && supabase test db`; inspect `EXPLAIN` on a representative indexed query.

During B25, `supabase db reset` and all database tests passed locally. The
representative active-Batch query used `batches_shop_expiry_idx`. No migration
was deployed as part of that verification pass.

**Dependencies:** B02 so new receive semantics are already defined.

### B10 — Map expiry-dashboard data in InventoryRepository

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-03. Focused repository/domain tests, relevant
inventory regressions, formatting, analysis, and `git diff --check` pass. B10
adds no new database surface. Its narrow correction to B09's undeployed contract
remains covered by B09's verification-pending pgTAP suite.

**Goal:** Expose a provider-neutral expiry snapshot from the inventory boundary.

**Why this is needed:** Riverpod/presentation must not map PostgREST rows or call Supabase.

**Current implementation:** `InventoryRepository.loadExpiryDashboard` returns
an immutable provider-neutral snapshot with B09's authoritative reference date
and typed active-stock items. The Supabase adapter strictly validates all B09
fields, exact Shop identity, calendar-day offsets, timestamps, and quantities;
it maps errors through existing typed repository semantics and classifies dated
items only with B08. Historical null expiry remains null/unclassified. The
in-memory adapter mirrors the contract with an explicit deterministic reference
date. B09's undeployed migration now emits one metadata-only row for an empty
Shop so the authoritative date is preserved; its pgTAP plan is 27 assertions
and remains verification-pending for B25.

**Scope:** Add immutable dashboard row/snapshot values and `loadExpiryDashboard`;
implement Supabase and in-memory adapters; reject malformed/cross-shop responses.

**Out of scope:** Do not add filtering/business buckets to the adapter or merge
this repository with storefront/catalog repositories.

**Files/components to inspect:** inventory application/data files,
`domain_models.dart`, Supabase and in-memory repository tests.

**Implementation steps:** Define minimal fields, call B09 RPC with explicit
shop ID, validate each row, mirror results in memory, and map failures to typed
repository exceptions.

**Acceptance criteria:** No Supabase type escapes data; unknown expiry remains
explicit; another-shop row fails closed.

**Verification:** focused inventory repository tests; `flutter analyze`.

Focused Supabase and in-memory adapter tests pass for populated and empty
snapshots, every risk boundary, nullable fields, quantities, cross-Shop rows,
malformed/inconsistent data, and backend/authorization failures. Domain and
receiving regressions, formatting, analysis, and `git diff --check` pass.

**Dependencies:** B09.

### B11 — Add the Riverpod expiry-dashboard controller

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-04. Focused controller, receiving, shop-session,
domain/inventory regressions, formatting, analysis, and `git diff --check` pass.
B11 changes no database surface and requires no pgTAP execution.

**Goal:** Load, bucket, retry, and refresh the active Shop’s expiry snapshot.

**Why this is needed:** The current Home is static, and business rules must not
move into the widget.

**Current implementation:** `expiryDashboardProvider` exposes current-Shop-only
async state backed by a private auto-disposed family `AsyncNotifier`. The family
key comes exclusively from `activeShopProvider`, physically separating Shop
request lifecycles so retained or late results cannot cross a Shop switch. Its
immutable state preserves B10's authoritative reference date and partitions the
existing B08 category into expired, today, next-7, 8–30, later, and needs-date
lists without recalculation. Explicit current-Shop refresh/retry is available,
overlapping requests retain only the latest result, and successful receiving
invalidates the current dashboard after persistence succeeds.

**Scope:** Add an auto-disposed/family `AsyncNotifier` scoped to explicit Shop
ID, use B08 classification over B10 rows, expose immutable bucket counts/lists,
and discard stale results after shop changes.

**Out of scope:** Do not schedule notifications or resolve Batches here.

**Files/components to inspect:** shop session provider, receiving/product
controllers for stale-shop patterns, new expiry application folder, tests.

**Implementation steps:** Load snapshot, partition unknown separately, provide
retry/refresh, invalidate after successful receiving, and cover loading/error/stale-shop transitions.

**Acceptance criteria:** Controller state has no widget/Supabase types and all
buckets derive from B08; a receive refreshes the active dashboard.

**Verification:** focused application tests plus receiving controller regression tests.

Focused tests pass for loading, populated and empty success, controlled
authorization/network/malformed errors, retry, refresh, overlapping requests,
Shop switching, stale responses, missing Shop, unchanged reference/category
values, no dashboard writes, and receive-triggered invalidation.

**Dependencies:** B08, B10.

### B12 — Replace the demo Home with the real expiry dashboard

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-04.

**Goal:** Owner/manager/worker see actual urgent stock with actionable bucket navigation.

**Why this is needed:** Hard-coded counts, currency risk, supplier returns, and
product dates are misleading in production.

**Current implementation:** Home consumes B11's current-Shop Riverpod state and
actions. It renders repository-backed risk summaries and Batch rows, represents
legacy unknown expiry separately, and keeps the shell-owned scan/receive route
prominent. The former static counts, dates, value-at-risk, supplier-return, and
inert action content have been removed.

**Scope:** Render B11 states with compact summary and buckets: Expired, Today,
Next 7 days, 8–30 days, Later, and Needs date for legacy data. Show Product,
expiry, quantity, and received date; provide loading, empty, error, retry, and
pull-to-refresh. Keep the scan/receive primary action.

**Out of scope:** Do not show invented value-at-risk, supplier returns,
analytics, reports, sales, or POS actions.

**Files/components to inspect:** `home_page.dart`, `app_shell.dart`, theme,
dashboard controller/models, app/widget tests.

**Implementation steps:** Replace demo composition, wire selected bucket lists,
open Batch details placeholder only when B15 is available, and remove inert buttons.

**Acceptance criteria:** Every visible number/date comes from repository state;
all required states are tested; no business bucketing occurs in widgets.

**Verification:** Home/dashboard widget tests and `test/app_shell_test.dart`
pass, including a deterministic 320x640 compact-screen layout check. Standard
Flutter tests, formatting, analysis, Android debug build, and diff checks pass.

**Dependencies:** B11; final Batch-row navigation depends on B15.

### B13 — Add an idempotent Batch-resolution RPC

**Priority:** PLAY STORE BLOCKER

**Goal:** Resolve all or part of active Batch quantity as disposed, returned, or cleared by adjustment while preserving audit history.

**Why this is needed:** V1 requires an expiring/expired Batch to be resolved and
history retained. Direct Batch/movement writes are intentionally denied.

**Current implementation:** Movement types/checks and unique idempotency keys
exist; no mutation changes `current_quantity` after receiving.

**Scope:** Add one security-definer RPC that authorizes membership, locks the
same-shop Batch, validates positive quantity not above current, inserts a
negative `disposed`, `returned`, or `adjusted` movement, and atomically decreases
`current_quantity`. Require a normalized reason for adjustment/clear. Exact
retries return the original outcome; changed payload conflicts.

**Out of scope:** Do not delete/archive history, implement sales/POS, edit prior
movements, or add supplier workflows.

**Files/components to inspect:** receiving migration/RPC, movement constraints,
rollback conventions, stock pgTAP suite, domain movement types.

**Implementation steps:** Define typed inputs/receipt, reuse the shop/idempotency
lock pattern, guard underflow and cross-shop access, pin search path/grants, and
test concurrency/idempotency/authorization.

**Acceptance criteria:** Quantity and one movement commit together; zero stock
remains queryable in history but disappears from active dashboard; failures write nothing.

**Verification:** `supabase db reset && supabase test db`; focused concurrency/manual SQL checks documented in implementation notes.

**Dependencies:** B09’s active-row semantics should be agreed first.

**Risk notes:** This is inventory-changing and must receive independent review.

### B14 — Add the Batch-resolution application boundary

**Priority:** PLAY STORE BLOCKER

**Goal:** Flutter can load Batch history and submit/retry one resolution safely.

**Why this is needed:** Presentation cannot call B13 or movement tables directly.

**Current implementation:** `InventoryRepository` has no Batch detail/history or
resolution methods; receiving shows the desired idempotency pattern.

**Scope:** Add Batch detail/movement-history reads, typed resolution request and
receipt, repository methods/adapters, a validating use case, and secure ID reuse
on uncertain retry.

**Out of scope:** Do not add sales, movement editing, batch expiry correction, or notification logic.

**Files/components to inspect:** inventory repository/use case/controller files,
secure ID generator, domain movement models, Supabase/in-memory repository tests.

**Implementation steps:** Define typed failure mapping, strictly map B13 result,
order history newest-first, enforce quantity/reason rules before RPC, and test exact retry/conflict.

**Acceptance criteria:** Cross-shop/malformed data fails closed; uncertain retry
uses the same key; successful resolution returns updated quantity and movement.

**Verification:** focused inventory application/data tests; existing receiving regressions.

**Dependencies:** B13.

### B15 — Add Batch detail, resolution, and history UI

**Priority:** PLAY STORE BLOCKER

**Goal:** From the dashboard, a member can inspect a Batch, resolve quantity,
and see immutable history.

**Why this is needed:** This closes the expiry-loss workflow for the pilot.

**Current implementation:** No Batch screen/controller exists; movement rows are member-readable.

**Scope:** Add a family `AsyncNotifier` keyed by Shop/Batch, a compact detail
screen, disposed/returned/cleared choices, quantity/reason validation,
confirmation, submission/retry states, and movement history. Refresh dashboard
and notification reconciliation after success.

**Out of scope:** Do not physically delete, edit movements, add supplier return
documents, sell flow, or automatic discounts.

**Files/components to inspect:** new expiry presentation/application files,
`home_page.dart`, B14 boundary, app routes/tests.

**Implementation steps:** Capture explicit identifiers, prevent double submit,
show server outcome, preserve form on failure, and navigate back with dashboard refresh.

**Acceptance criteria:** Full/partial resolution works; zero-quantity Batch remains
in history; loading/empty/error/retry and role-neutral member access are tested.

**Verification:** focused controller/widget tests; `flutter test test/features/inventory test/features/expiry`; standard Flutter checks.

**Dependencies:** B12, B14.

### B16 — Add shop-owned Product correction to the repository

**Priority:** POST-PILOT

**Goal:** Correct a shop Product name/brand/image metadata without changing global catalog data.

**Why this is needed:** External data may be incomplete or wrong, and shop
corrections must remain shop-local. No supported edit boundary exists today.

**Current implementation:** `products` is shop-owned and updateable through RLS;
optional `catalog_product_id` does not replace it.

**Scope:** Add a focused update method to the Product catalog boundary,
Supabase/in-memory adapters, normalization, same-shop response validation, and tests.

**Out of scope:** Do not mutate `catalog_products`, reassign barcodes, archive
Products, or build catalog merging.

**Files/components to inspect:** catalog repository/adapters, Product mapping,
catalog RLS pgTAP, data/application tests.

**Implementation steps:** Accept only editable shop fields, preserve source and
catalog link, use explicit Shop/Product IDs, and fail closed on cross-shop/missing rows.

**Acceptance criteria:** Same-shop correction succeeds and leaves Batch/barcode
identity unchanged; cross-shop and anon writes remain denied.

**Verification:** focused repository tests and catalog pgTAP; standard Flutter checks.

**Dependencies:** B05 should establish the intended Shop-setting policy first; Product policy remains member-scoped.

### B17 — Add minimal Product correction UI

**Priority:** POST-PILOT

**Goal:** A member can correct the selected Product before/after receiving without losing the Batch workflow.

**Why this is needed:** B16 is not useful to pilot shops without an accessible,
small edit surface.

**Current implementation:** Resolved Product and receiving screens display
metadata but offer no correction action.

**Scope:** Add a feature-scoped Riverpod edit controller and one minimal form
for name, optional brand, and optional valid HTTP(S) image URL. Return the
updated Product to the caller and refresh Product lists.

**Out of scope:** Do not edit barcodes, source, catalog links, prices, batches,
or add image upload/storage.

**Files/components to inspect:** Product resolution/receiving presentation,
catalog controllers, B16 method, tests.

**Implementation steps:** Capture active Shop, validate fields, block duplicate
submits, preserve draft on error, and expose entry from found/selected Product.

**Acceptance criteria:** Correction updates only the shop Product; ongoing
receiving uses the corrected result; all workflow states are tested.

**Verification:** focused Product controller/widget tests and receiving regressions.

**Dependencies:** B16.

## P2 — Security and long-lived data integrity

### I01 — Remove the one-shop-per-user database restriction safely

**Priority:** POST-PILOT

**Goal:** Allow one user to hold memberships in several Shops while preserving
one active Shop in the client.

**Why this is needed:** The preferred durable model is many memberships. The
Flutter session already lists/selects multiple, but database uniqueness and
several RPC checks contradict it.

**Current implementation:** `shop_memberships_user_id_key`, join/create/review
RPCs, and one pending-request index/check enforce one Shop per user. Domain docs
currently describe that deployed restriction.

**Scope:** In one corrective migration, drop only the user-wide membership
unique constraint, preserve composite membership uniqueness, and update
create/join/review checks to be target-Shop-specific. Decide and document whether
one pending request per user remains a deliberate V1 throttle. Add pgTAP and
Flutter multi-membership selection regressions.

**Out of scope:** Do not add branches, cross-Shop inventory, ownership transfer,
or simultaneous multi-Shop workflow state.

**Files/components to inspect:** multi-user/invite migrations and tests,
`shop_session_controller.dart`, in-memory Shop repository, domain/architecture docs.

**Implementation steps:** Audit dependent constraints/RPCs, migrate without row
rewrites, test existing and new membership cases, then update docs/comments that
still say “1-shop-per-user model.”

**Acceptance criteria:** Existing rows are unchanged; a user can belong to two
Shops; same-Shop duplicate membership is impossible; active Shop remains explicit.

**Verification:** `supabase db reset && supabase test db`; shop-session tests with 0/1/2 memberships; linked dry-run review.

**Dependencies:** B06/B07 should land first so multi-Shop role administration has tested semantics.

**Risk notes:** Membership semantics are security-sensitive; review the complete migration independently.

## P3 — Notifications and owner visibility

### B18 — Define a deterministic, low-noise notification policy

**Priority:** PLAY STORE BLOCKER

**Goal:** Convert active dated Batches into aggregated Shop reminders at 30, 15,
7, 3, 1, and 0/expired thresholds.

**Why this is needed:** Notification rules must be shared/tested outside screens,
and per-Batch alerts would become noisy.

**Current implementation:** `NotificationProvider` and request type are unused;
no policy or settings exist.

**Scope:** Define pure Dart policy input/output, aggregate Batches into at most
one Shop summary per threshold/delivery time, use stable request IDs, exclude
unknown/zero quantity, and make the delivery hour explicit. Owners/managers are
eligible; workers produce no requests.

**Out of scope:** Do not call platform plugins, persist remote settings, send
push notifications, or add custom thresholds.

**Files/components to inspect:** `external_providers.dart`, B08 risk service,
Shop roles, new notification domain/application tests.

**Implementation steps:** Evolve the unused request contract for summaries,
inject clock/Shop timezone inputs, define deduplication/cancellation IDs, and
test boundaries, aggregation, role eligibility, and DST transitions as values.

**Acceptance criteria:** Same input yields the same bounded request set; no
screen owns thresholds; workers/unknown/cleared Batches schedule nothing.

**Verification:** focused pure Dart notification tests; `flutter analyze`.

**Dependencies:** B08, B10.

### B19 — Implement the local notification adapter and Android setup

**Priority:** PLAY STORE BLOCKER

**Goal:** Initialize, request permission for, schedule, enumerate, and cancel
local expiry notifications on Android.

**Why this is needed:** The port has no infrastructure implementation.

**Current implementation:** No notification dependency, Android permission, or
bootstrap initialization exists.

**Scope:** Add the smallest maintained local-notification and timezone packages,
record the dependency/ADR reason, implement the adapter behind the existing
port, create one Android channel, use inexact scheduling, handle Android 13+
permission, and provide an in-memory adapter for tests.

**Out of scope:** Do not add Firebase/APNs, exact alarms, background services,
marketing notifications, or remote preferences.

**Files/components to inspect:** `pubspec.yaml`, app dependencies/bootstrap,
notification port, Android manifest/Gradle, decisions docs, adapter tests.

**Implementation steps:** Initialize timezone data and plugin before use, map
stable string IDs safely, expose permission state, add manifest entries, and
test adapter calls with a mockable wrapper rather than platform channels in unit tests.

**Acceptance criteria:** A release build can request permission and manage only
the app’s expiry channel; denial is recoverable; no exact-alarm permission is required.

**Verification:** focused adapter tests; `flutter analyze`; Android release APK/AAB build; physical Android permission smoke test.

**Dependencies:** B18.

**Risk notes:** New dependencies require the ADR mandated by `AGENTS.md`.

### B20 — Add the notification reconciliation coordinator

**Priority:** PLAY STORE BLOCKER

**Goal:** Pending local reminders automatically match current active Batches for
the eligible active Shop.

**Why this is needed:** Scheduling only from a screen or only on receive leaves
stale reminders after resolution and misses changes made on another device.

**Current implementation:** No coordinator exists; receiving and future
resolution controllers have clear success points.

**Scope:** Add a Riverpod/application coordinator that loads current dashboard
data, computes B18 requests, compares B19 pending requests, and applies the
minimal schedule/cancel delta. Run on eligible Shop-session entry, app resume,
successful receive, and successful resolution. Serialize overlapping reconcile calls.

**Out of scope:** Do not poll continuously, put rules in screens, or send server push.

**Files/components to inspect:** app composition/shell lifecycle,
shop-session/receiving/resolution controllers, dashboard repository, notification adapters/tests.

**Implementation steps:** Capture user/Shop role, handle permission denial as
state not crash, reconcile idempotently, cancel app-owned reminders on sign-out
or worker role, and log only safe categories/counts.

**Acceptance criteria:** Create/change/resolve/sign-out/resume scenarios converge
to the correct pending set; retries do not duplicate; screens contain no scheduling rules.

**Verification:** coordinator tests with fake clock/repository/provider; receiving and resolution regressions; physical-device schedule/cancel check.

**Dependencies:** B15, B18, B19.

### B21 — Replace Alerts placeholder with notification status and retry UI

**Priority:** PLAY STORE BLOCKER

**Goal:** Owner/manager can see whether expiry reminders are active, grant
permission, and retry reconciliation; workers see a clear role explanation.

**Why this is needed:** Android permission denial otherwise makes “notifications work” unverifiable and unactionable.

**Current implementation:** `AppShell` renders `Center(Text('Alerts'))`.

**Scope:** Build a compact Riverpod-driven Alerts screen showing permission,
last reconciliation result, pending summary count, request/open-settings action,
loading/error/retry, and fixed default thresholds. Do not duplicate coordinator rules.

**Out of scope:** Do not add custom thresholds, quiet hours, push tokens, or per-Batch toggles.

**Files/components to inspect:** `app_shell.dart`, B19/B20 state, app theme, widget tests.

**Implementation steps:** Replace shell placeholder, role-gate actions, expose
OS settings fallback after denial, and test all permission/reconcile states.

**Acceptance criteria:** Eligible users can recover from denial/error and verify
scheduled summaries; workers never schedule and do not see misleading controls.

**Verification:** Alerts widget/controller tests; app-shell regression; Android manual permission checks.

**Dependencies:** B20.

## P4 — Production UX and account recovery

### I02 — Add email password-reset flow

**Priority:** PLAY STORE BLOCKER

**Goal:** A pilot user who forgets a password can request and complete recovery.

**Why this is needed:** Basic sign-in works, but support currently has no
recoverable path. This is important for a real pilot but does not block internal build work.

**Current implementation:** `AuthService` supports sign-up/sign-in/sign-out only;
`supabase_flutter` includes recovery primitives and app-links transitively.

**Scope:** Add narrow auth methods/controller states, recovery request UI, deep
link callback handling, new-password form, and safe generic confirmation text.

**Out of scope:** Do not add social auth, MFA, account deletion, or custom email infrastructure.

**Files/components to inspect:** auth service/adapters/controller/gate tests,
Android manifest/deep-link configuration, Supabase Auth redirect settings.

**Implementation steps:** Define redirect configuration, avoid account-existence
leaks, handle expired links, and test request/callback/error states.

**Acceptance criteria:** A configured pilot account can recover on Android; invalid
links fail safely; existing auth flow regresses cleanly.

**Verification:** focused auth tests and one real-device Supabase recovery smoke test.

**Dependencies:** B22 production environment values should be settled first.

## P5 — Android production configuration and observability

### B22 — Add an explicit production environment build contract

**Priority:** PILOT BLOCKER

**Status:** Implementation complete on 2026-09-04; verification pending the
human-owned production public values and physical-device build/install check.

**Goal:** Every release artifact is unmistakably built with validated production defines.

**Why this is needed:** `APP_ENV` defaults to development and is absent from the
example used during inspection, so a release AAB can still show development behavior.

**Current implementation:** `AppEnvironment` centrally validates compile-time
and JSON build values. Production requires an explicit environment, HTTPS
Supabase endpoint, matching production project reference, recognizable
client-safe key, and explicit storefront state. The pilot APK wrapper rejects
invalid/non-production files before invoking Flutter/Gradle; local production
files remain ignored and the committed example contains placeholders only.

**Scope:** Document/create a safe production config template or build script that
requires `APP_ENV=production`, production Supabase public values, and explicit
storefront flag. Fail before Gradle when required values are absent/wrong.

**Out of scope:** Do not commit service-role secrets, signing secrets, or add a remote flag service.

**Files/components to inspect:** `app_environment.dart`, `config/`, `.gitignore`,
README, Android build commands, environment tests.

**Implementation steps:** Add validation/tests, document secret ownership, and
provide exact debug/staging/production commands without scattering endpoints.

**Acceptance criteria:** A production-configured pilot APK cannot silently use
development flavor or a server-only key; storefront is explicitly disabled;
client-safe config remains centralized and ignored where appropriate.

**Verification:** Focused environment tests pass (18 tests); focused analysis
passes; the preflight wrapper rejects the development example with exit 64
before Flutter/Gradle. The production-configured release APK build/install
remains pending approved local values and the pilot device. Web/AAB builds do
not gate the controlled sideloaded pilot.

**Dependencies:** B01.

### B23 — Set the immutable Android application identity and branding

**Priority:** PLAY STORE BLOCKER

**Goal:** Replace template package/name/icon with the approved pilot identity before Play upload.

**Why this is needed:** The built manifest is `com.example.product_expiry_management`
with template label. Play package IDs are expensive/impossible to change after publication.

**Current implementation:** Package/namespace and Kotlin package use `com.example...`;
application label is `product_expiry_management`; template launcher icons remain.

**Scope:** After human approval of final application ID, display name, and icon,
update Gradle namespace/applicationId, Kotlin source path/package, manifest label,
launcher assets, and related tests/docs.

**Out of scope:** Do not guess the company domain, rename Dart packages, redesign
the whole UI, or configure iOS as a blocker.

**Files/components to inspect:** `android/app/build.gradle.kts`, main manifest,
`MainActivity.kt`, mipmap assets, pubspec version, Play Console availability.

**Implementation steps:** Record approved immutable values, change all Android
references atomically, build/install, inspect merged manifest, and confirm no old package remains.

**Acceptance criteria:** Release manifest exactly matches approved identity;
launcher name/icon are pilot-ready; camera/auth flows still launch.

**Verification:** `rg 'com\.example|product_expiry_management' android`; release APK install; `aapt2 dump badging` or merged-manifest inspection.

**Dependencies:** Human supplies the approved values; B22.

**Risk notes:** Do not execute this task until the Play package ID owner confirms the value.

### B24 — Configure non-debug Android release signing

**Priority:** PLAY STORE BLOCKER

**Goal:** Release artifacts use the approved upload key without committing credentials.

**Why this is needed:** `build.gradle.kts` explicitly signs release with the
Android Debug certificate. The inspected AAB signer is `CN=Android Debug`.

**Current implementation:** No `key.properties`, upload keystore, release signing
config, or secret-handling documentation exists.

**Scope:** Add standard ignored signing-property support, require all release
fields, fail closed rather than fall back to debug, document key backup/rotation
ownership, and leave debug builds unchanged.

**Out of scope:** Do not generate or upload a production key without the release
owner, commit credentials, or enable obfuscation as an unrelated change.

**Files/components to inspect:** Android Gradle file, `.gitignore`, README/release docs, Play App Signing setup.

**Implementation steps:** Load ignored properties/environment, define release
signing config, validate missing fields, obtain owner-managed upload key, build,
and inspect certificate subject/fingerprint.

**Acceptance criteria:** Release build cannot use debug signer; secrets are
ignored; key recovery ownership is documented; Play accepts the upload certificate.

**Verification:** release AAB build; `/opt/homebrew/opt/openjdk@17/bin/jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab`; confirm signer is not `Android Debug`.

**Dependencies:** B23 and human/Play signing decisions.

**Risk notes:** Key loss can block updates; use Play App Signing and backed-up upload-key procedures.

### I03 — Add crash reporting through the existing logging boundary

**Priority:** POST-PILOT

**Goal:** Capture redacted Flutter/platform/async crashes from pilot builds.

**Why this is needed:** Error hooks and `AppLogger` exist, but failures are only local.

**Current implementation:** `bootstrap.dart` captures three global error paths;
no SDK/DSN/consent configuration exists.

**Scope:** Once the release owner selects/provisions the service, add one adapter
behind `AppLogger` or a narrow crash port, production-only initialization,
environment DSN validation, release version tagging, and redaction tests/docs.

**Out of scope:** Do not log barcodes, inventory values, email addresses, auth
tokens, OCR images, or add product analytics in this task.

**Files/components to inspect:** bootstrap/logger/environment, pubspec, privacy/security docs, provider SDK docs.

**Implementation steps:** Record dependency rationale/ADR, initialize before
`runApp`, forward caught/unhandled errors once, scrub context, and verify a
controlled test event in a non-production project.

**Acceptance criteria:** Pilot crashes arrive with environment/version and no
sensitive payload; missing DSN behavior is explicit; local tests need no network.

**Verification:** logger/bootstrap tests, analyze/build, staging test event in dashboard.

**Dependencies:** Human selects the service and supplies a staging/production DSN; B22.

### I04 — Add reproducible CI quality gates

**Priority:** POST-PILOT

**Goal:** Run formatting, analysis, Flutter tests, and release-build smoke checks on every change.

**Why this is needed:** Local checks pass, but no `.github` or other CI config exists.

**Current implementation:** README lists local commands; pgTAP requires a local
Supabase runtime; direct dependencies are current.

**Scope:** Add CI for locked Flutter version, dependency fetch, format, analyze,
full test, web build, and Supabase db reset/pgTAP. Add an unsigned/debug-signing
Android build smoke if secrets are unavailable; keep signed release in protected CI.

**Out of scope:** Do not deploy production on every push or expose env/signing secrets.

**Files/components to inspect:** repository host, pubspec/lock, Supabase config/tests,
release config docs.

**Implementation steps:** Cache safely, pin tool versions, supply test-only public
config, start/stop Supabase, upload useful failure artifacts, and document protected release job.

**Acceptance criteria:** A clean checkout reproduces all gates; failures block
merge; no production credential appears in logs/artifacts.

**Verification:** Run the workflow on a test branch and compare its commands to local results.

**Dependencies:** B22; B24 for protected signed-release job only.

## P6 — Release verification and rollout

### B25 — Verify and deploy the complete migration chain

**Priority:** PILOT BLOCKER

**Status:** Complete on 2026-09-04. The reviewed five-migration chain was
verified locally, explicitly authorized, deployed through the linked CLI
workflow, and verified read-only on the linked project.

**Goal:** In one checkpoint, prove the full reviewed local migration chain and
then make the linked pilot project match it before client rollout.

**Why this is needed:** The storefront migration is already pending and local
pgTAP could not run because Docker/PostgreSQL was unavailable. Later core
migrations will extend that pending chain.

**Current implementation:** Local and linked histories match through
`20260901030000`; there are no remote-only versions. The reviewed local-only
chain is `20260901040000`, `20260901050000`, `20260902000000`,
`20260903000000`, and `20260903110406`. A reusable Colima/Docker local Supabase
stack reset the complete eleven-migration chain from zero. All eight pgTAP files
passed (187/187 assertions), local lint completed with two pre-existing
non-blocking warnings in `rotate_shop_invite_code`, and the B09 representative
query used `batches_shop_expiry_idx`. The linked dry-run still lists exactly the
five reviewed local-only migrations. After the authorized push, local and remote
histories match through `20260903110406`, the linked dry-run is empty,
error-level linked lint passes, and 18 read-only catalog checks confirm the
reviewed functions, views, policies, RLS, indexes, and grants. B02, B03, B05,
B06, and B09 remain complete. `ENABLE_STOREFRONT=false` remains the pilot
setting.

**Scope:** On one working local, staging, or otherwise approved PostgreSQL/
Supabase verification environment, reset from zero, execute every pgTAP suite,
lint/diff, and close the database-verification portions of B02, B03, B05, B06,
and B09 together. Then review the linked dry-run, take the approved
backup/recovery checkpoint, apply the complete reviewed migration chain once,
and confirm linked/local histories match.

**Out of scope:** Do not alter production manually in Dashboard, repair history
by marking versions without evidence, or deploy from an unreviewed dirty diff.

**Files/components to inspect:** every migration/rollback/test, implementation
notes/review findings, linked project ID, Supabase CLI output.

**Implementation steps:** Start local stack, reset/test twice, inspect schema
diff and grants, record backup/recovery plan, run linked dry-run, obtain release
authorization, push, then re-list history and run non-mutating smoke queries.

**Acceptance criteria:** All pgTAP assertions pass in the approved verification
environment; B02, B03, B05, B06, and B09 database verification is recorded from
that same pass; dry-run contains only reviewed files; remote/local versions
match after the authorized push; RLS smoke tests pass. B01's storefront flag
remains disabled for the pilot regardless of whether its preserved additive
migration is present in the linear chain.

**Verification:** `supabase start`; `supabase db reset`; `supabase test db`;
`supabase db lint --local`; `supabase migration list --linked`;
`supabase db push --linked --dry-run`; authorized `supabase db push --linked`;
final `supabase migration list --linked`.

**Dependencies:** B02, B03, B05, B06, and B09 implementation; review of every
local migration in the chain; a working approved database runtime; human
authorization and recovery ownership for the linked push. Deferred
PLAY STORE BLOCKER and POST-PILOT migrations are not prerequisites.

**Risk notes:** Supabase security advisors report generic warnings for intended
authenticated security-definer RPCs and two older roster RPCs callable by
`anon`; direct linked checks confirm both older RPCs reject anonymous callers.
Existing informational index/policy-efficiency findings remain outside B25.

### B26 — Run the real-device critical-path smoke matrix

**Priority:** PILOT BLOCKER

**Goal:** Prove the pilot workflow on physical Android devices against the pilot Supabase project.

**Why this is needed:** Unit/widget/pgTAP tests cannot prove Android
installation, camera permission, email confirmation, restart persistence, or
real-device interaction with the pilot backend.

**Current implementation:** No `integration_test/` suite or recorded pilot smoke matrix exists.

**Scope:** Install a production-configured Android APK on a physical device and
run the minimum pilot journey: owner signup and email confirmation, Shop
creation, optional worker invite/join/approval, one barcode resolution path,
one barcode-less Product creation, quantity plus mandatory-expiry receive,
restart/reload persistence, actionable dashboard display, recoverable network
error, sign-out/in, and a second-account Shop-isolation check.

**Out of scope:** Do not gate the pilot on manager promotion, Product correction,
Batch resolution/history UI, local notifications, Play signing/upload, OCR,
POS, customer checkout, iOS polish, or load/performance at scale.

**Files/components to inspect:** release checklist, Supabase Auth settings/test
accounts, Android permission config, all acceptance criteria.

**Implementation steps:** Prepare reversible test data, record build/backend
versions, execute the matrix, capture failures without personal data, fix via
separate scoped tasks, rerun from a clean install, and retain results.

**Acceptance criteria:** The production-configured APK installs and starts on the
pilot device; the stated receive-and-see-expiry journey passes against the
verified backend; camera denial and network failure are recoverable through an
available manual/retry path; data survives restart; another Shop's data is never
visible. Non-debug Play signing is not required for this controlled sideload.

**Verification:** Recorded PASS/FAIL matrix, installed APK package/version/config
evidence, relevant Supabase Batch/movement rows, and explicit Shop-isolation
observations without personal data.

**Dependencies:** B04, B12, B22, B25, an Android device, pilot Supabase public
configuration, test email access, and owner/second-account test credentials.

### B27 — Produce and hand off the closed-pilot Android release

**Priority:** PLAY STORE BLOCKER

**Goal:** Deliver one versioned, signed, verified AAB to the Play closed-testing track with rollback notes.

**Why this is needed:** A successful local build is not a release until artifact,
configuration, signing, backend version, and rollout ownership are fixed.

**Current implementation:** `0.1.0+1` AAB builds after a clean Gradle run, but it
is debug-signed and no Play handoff checklist exists.

**Scope:** Set approved version/build number, run the complete verification suite,
build with production defines/signing, verify certificate/package/version,
generate symbols if enabled, upload to closed testing, add a small tester cohort,
and document rollback/support monitoring.

**Out of scope:** Do not promote to open/production, deploy unrelated backend
changes, or claim iOS readiness.

**Files/components to inspect:** pubspec version, production config, Android
Gradle/manifest, migration history, crash dashboard if I03 completed, Play Console.

**Implementation steps:** Clean generated outputs, run gates, build once, hash
artifact, inspect signer/manifest, upload, complete required Play metadata/data
safety accurately, stage rollout, and monitor first sessions.

**Acceptance criteria:** Play accepts the non-debug-signed artifact for the
approved package; installed build reaches the verified backend; tester/support
and rollback owners are named.

**Verification:** `dart format --output=none --set-exit-if-changed lib test`;
`flutter analyze`; `flutter test`; `supabase migration list --linked`;
`flutter build web --dart-define-from-file=config/env.production.json`;
`flutter build appbundle --release --dart-define-from-file=config/env.production.json`;
`jarsigner -verify -verbose -certs ...`; Play closed-track validation.

**Dependencies:** B22–B26. I03 is strongly recommended but may be waived by the release owner for a tiny pilot.

**Risk notes:** Upload/promotion is an external release action and requires explicit authorization.

## P7 — Deliberately deferred post-release work

### P01 — Enable and evolve the public storefront

**Priority:** POST-RELEASE

**Goal:** Turn on the preserved storefront only after its migration/RLS and pilot value are separately approved.

**Why this is needed:** The surface is nearly complete but optional; activating it
should follow privacy verification instead of delaying the expiry pilot.

**Current implementation:** Complete Flutter/schema foundation, static flag from B01, migration/pgTAP present.

**Scope:** Validate public privacy, set `ENABLE_STOREFRONT=true` for a chosen build,
and later add reviewed catalog matching/image management.

**Out of scope:** No orders, checkout, payments, public stock quantity, or automatic expiry deals.

**Files/components to inspect:** storefront feature, migration/test, B01 config.

**Implementation steps:** Re-run pgTAP, complete anonymous manual tests, enable in staging, then decide pilot exposure.

**Acceptance criteria:** Only enabled profiles/published listings/server-active deals are public; private inventory remains denied.

**Verification:** storefront Flutter tests and `public_storefront_rls.test.sql`.

**Dependencies:** B25.

### P02 — Add custom notification preferences and server push

**Priority:** POST-RELEASE

**Goal:** Move beyond fixed local summary reminders when pilot feedback proves the need.

**Why this is needed:** Custom settings and push add operational cost that is
justified only if local summaries are insufficient.

**Current implementation:** B18–B21 provide the planned fixed-threshold local
policy, adapter, reconciliation, and permission/status surface.

**Scope:** Shop/user preferences, quiet hours, push-token lifecycle, server scheduler, and local/push deduplication behind the existing coordinator.

**Out of scope:** Do not change expiry classification or make workers recipients by default without product approval.

**Files/components to inspect:** notification domain/application/data/presentation
from B18–B21, Shop roles, security docs, future push-provider documentation.

**Implementation steps:** Gather pilot feedback, specify settings ownership/RLS,
add one preference slice, add push token/delivery behind the port, then test
local/push deduplication before enabling it.

**Files/components to inspect:** B18–B21 notification boundaries and security docs.

**Acceptance criteria:** Preference/RLS/push retry semantics have separate approved specs and tests.

**Verification:** unit, pgTAP, integration, and multi-device delivery tests.

**Dependencies:** B20 and real pilot notification feedback.

### P03 — Add OCR expiry suggestions

**Priority:** POST-RELEASE

**Goal:** Suggest dates while preserving mandatory user validation.

**Why this is needed:** OCR may reduce entry time later, but it must not weaken
the reliable manual date workflow needed for launch.

**Current implementation:** A provider-neutral recognition port and observation
domain types exist; no adapter, capture workflow, confidence service, or schema exists.

**Scope:** Provider adapter, confidence policy, candidate confirmation, and observation audit.

**Out of scope:** Never auto-persist low-confidence or ambiguous dates.

**Files/components to inspect:** expiry-recognition port, receiving flow,
domain observations, camera/privacy docs, candidate parsing tests.

**Implementation steps:** Select/provider-review one adapter, define deterministic
confidence/date-type rules, build candidate confirmation, persist only confirmed
observations, and preserve manual fallback throughout.

**Files/components to inspect:** expiry-recognition port, domain observations, security/privacy docs.

**Acceptance criteria:** Manual date entry remains fully usable; every suggestion is validated before persistence.

**Verification:** deterministic parsing/confidence tests and device image tests.

**Dependencies:** Core pilot workflow and a provider/privacy decision.

### P04 — Add offline receiving/outbox synchronization

**Priority:** POST-RELEASE

**Goal:** Support unreliable networks after online-first pilot behavior is measured.

**Why this is needed:** A local database/outbox is expensive and should solve
observed connectivity failures rather than become speculative release work.

**Current implementation:** Online repositories expose typed retry states and
server idempotency keys; no local persistence or sync engine exists.

**Scope:** Explicit local store/outbox, idempotency reuse, conflict states, and reconciliation.

**Out of scope:** No broad Drift rewrite or silent last-write-wins.

**Files/components to inspect:** inventory use cases/repositories/controllers,
idempotency migrations/tests, architecture and decision docs.

**Implementation steps:** Measure failure cases, specify draft/outbox state,
implement one receiving-only queue behind existing boundaries, reconcile exact
server receipts, then expand only from proven needs.

**Files/components to inspect:** inventory use cases, idempotency contracts, architecture ADRs.

**Acceptance criteria:** Offline drafts never appear server-saved early; retry cannot double stock.

**Verification:** offline/reconnect/conflict integration suite.

**Dependencies:** Pilot connectivity evidence.

### P05 — Add privacy-conscious product analytics

**Priority:** POST-RELEASE

**Goal:** Measure the small approved event set after consent/provider decisions.

**Why this is needed:** Analytics is useful for prioritization but does not
deliver expiry prevention and introduces privacy/provider decisions.

**Current implementation:** No analytics port, SDK, event schema, or consent flow exists.

**Scope:** Narrow analytics port, redacted events, environment controls, and tests.

**Out of scope:** No raw barcode, email, inventory value, or OCR payload collection.

**Files/components to inspect:** bootstrap/config/logger, core workflow success
points, security/privacy docs, selected provider documentation.

**Implementation steps:** Approve a minimal event schema, add a narrow port and
no-op/test adapter, initialize production consent/config, instrument application
success points, and audit payloads before enabling delivery.

**Acceptance criteria:** Event schema/privacy review is approved and analytics never blocks core workflows.

**Verification:** adapter tests and staging dashboard checks.

**Dependencies:** Privacy owner/provider selection.

### P06 — Add Arabic localization and RTL QA

**Priority:** POST-RELEASE

**Goal:** Add Arabic without embedding Qatar logic in the domain.

**Why this is needed:** Arabic improves regional adoption, but translation work
should follow stable pilot workflows and copy.

**Current implementation:** Flutter UI strings are inline English; domain dates
and currency/timezone values are provider-independent.

**Scope:** Flutter localization resources, English/Arabic strings, RTL layout/device QA.

**Out of scope:** No multi-country compliance engine.

**Files/components to inspect:** all presentation strings, `MaterialApp`, theme,
date/currency formatters, domain value objects, Android locale behavior.

**Implementation steps:** Add Flutter localization configuration/resources,
extract core flow strings, translate/review Arabic, fix RTL layout issues, and
run both locale smoke matrices.

**Acceptance criteria:** Core pilot flow works in both locales with unchanged domain rules.

**Verification:** locale widget tests and Arabic device smoke matrix.

**Dependencies:** Stable pilot copy.

### P07 — Add membership removal and ownership transfer

**Priority:** POST-RELEASE

**Goal:** Safely administer departures and Shop ownership after the pilot role model is proven.

**Why this is needed:** These are security-sensitive lifecycle operations that
are not required for the first invite/approval workflow.

**Current implementation:** Owners can review joins and B06/B07 will manage
manager/worker roles; there is no removal or ownership-transfer boundary.

**Scope:** Separate reviewed RPCs, last-owner protection, audit history, UI/tests.

**Out of scope:** No custom permission builder or organization hierarchy.

**Files/components to inspect:** membership migrations/RPCs/pgTAP, Shop
repository/controller/screen, audit/history decisions.

**Implementation steps:** Specify last-owner and self-removal rules, add separate
transactional RPCs with audit records, expose owner-only application methods,
then add confirmation UI and concurrency tests.

**Acceptance criteria:** A Shop can never lose its last owner; every action is auditable and tenant-scoped.

**Verification:** concurrency/authorization pgTAP and role UI tests.

**Dependencies:** B06/B07 and I01.

### P08 — Migrate Android plugins to built-in Kotlin compatibility

**Priority:** POST-RELEASE

**Goal:** Remove Gradle 10/future Flutter deprecation warnings without destabilizing the pilot build.

**Current implementation:** Release build passes, but Flutter reports
`mobile_scanner` applying legacy KGP and Gradle reports deprecated compatibility flags.

**Why this is needed:** The warning predicts incompatibility with a future
Flutter/Gradle toolchain, but changing the build stack before pilot adds avoidable risk.

**Scope:** Re-evaluate plugin releases, upgrade only with regression evidence,
then migrate Gradle settings to built-in Kotlin.

**Out of scope:** Do not upgrade the toolchain during final release hardening merely to remove warnings.

**Files/components to inspect:** `pubspec.yaml`/lock, Android settings and
properties, Flutter migration guidance, release notes for every affected plugin.

**Implementation steps:** Reproduce on a branch, identify versions with built-in
Kotlin support, upgrade one dependency/tool layer at a time, remove compatibility
flags only when supported, and regression-test scanning/share/auth.

**Acceptance criteria:** Clean Android build has no legacy-KGP warning and scanner/share/auth regressions pass.

**Verification:** full Flutter tests and clean release AAB on the pinned/new toolchain.

**Dependencies:** After the first pilot artifact is reproducible.

### P09 — Reconcile repository hygiene and desktop templates

**Priority:** POST-RELEASE

**Goal:** Decide which untracked generated desktop/scratch files belong in the repository.

**Why this is needed:** The dirty/untracked templates obscure review scope but
do not affect the Android runtime and may contain user work.

**Current implementation:** `linux/`, `macos/`, `windows/`, `scratch/sample_app/`,
and `tmp.dart` are untracked in the inspected worktree.

**Scope:** Inventory ownership, update ignores, retain intentional platforms, and remove only with explicit approval.

**Out of scope:** Do not delete user work or make desktop readiness a pilot blocker.

**Files/components to inspect:** `git status`, `.gitignore`, Flutter platform
directories, scratch/temp files, user ownership context.

**Implementation steps:** Ask the owner to classify each path, retain intentional
platforms, ignore reproducible generated files, remove only explicitly approved
disposable content, and verify a clean checkout.

**Acceptance criteria:** A clean checkout contains only intentional sources/generated-policy files.

**Verification:** `git status --short`, clean-clone format/analyze/test.

**Dependencies:** Human ownership confirmation.

### P10 — Evaluate later commercial/customer modules separately

**Priority:** POST-RELEASE

**Goal:** Keep POS, suppliers, deals automation, orders, payments, loyalty,
advanced analytics, and compliance from entering the core release accidentally.

**Why this is needed:** Each module changes product scope, data/security, or
billing semantics and cannot safely be treated as incidental cleanup.

**Current implementation:** Some domain extension types/storefront foundation
exist, but none of these commercial modules is an approved core workflow.

**Scope:** Each approved module receives a separate product spec, data/privacy
boundary, migration plan, and Medium-sized vertical slices.

**Out of scope:** No speculative implementation under this umbrella task.

**Files/components to inspect:** pilot feedback, product spec, domain model,
architecture/security docs, relevant future provider requirements.

**Implementation steps:** Select one evidence-backed module, write explicit
acceptance/data/privacy rules, decompose it into separate vertical slices, and
obtain product approval before implementation.

**Acceptance criteria:** No module starts without explicit pilot evidence and acceptance criteria.

**Verification:** Product/architecture review, then task-specific commands.

**Dependencies:** Pilot feedback and explicit product approval.

## Task counts and critical path

- **Completed:** B01, B02, B03, B04, B05, B06, B08, B09, B10, B11, B12, and
  B25.
- **Implementation complete / verification pending:** B22.
- **Remaining PILOT BLOCKER:** 2 tasks (B22, B26).
- **Remaining PLAY STORE BLOCKER:** 11 tasks (B07, `B13`–`B15`, `B18`–`B21`,
  B23, B24, B27).
- **Remaining POST-PILOT B task:** 2 tasks (B16, B17).
- **Other deferred work:** I01, I03, I04, and `P01`–`P10` are POST-PILOT; I02
  is a PLAY STORE BLOCKER.

The next executable PILOT BLOCKER is **B26 — Run the real-device critical-path
smoke matrix**.

The pilot implementation order is:

`B26`

Run `B26` for physical-device acceptance and the remaining B22 build/install
check against the now-verified linked database.

As of 2026-09-04, two later local migrations are independently verified but
not deployed: `20260903225832_require_receive_selling_price.sql` and
`20260904100647_global_catalog_barcode_resolution.sql`. They must be reviewed in
that order through the normal linked migration workflow before B26 uses the
updated receiving/catalog contracts. This is a deployment checkpoint, not a
new application feature task; Cloudinary/image-contribution Migration 2 remains
out of scope.
No B07, Batch-resolution, notification, Product-correction, Play identity,
Play-signing, or Play-upload task is on the first-shop critical path.

## Human/product inputs that cannot be guessed

Before the first real-shop pilot, a human must:

1. Supply and verify the pilot Supabase URL and publishable/anon client key,
   email-confirmation/redirect settings, and `APP_ENV=production` configuration
   with `ENABLE_STOREFRONT=false` for B22.
2. Provide the Android device, pilot shopkeeper/tester, test email access, and a
   second account for the Shop-isolation portion of B26; approve the APK's
   controlled sideload and the handling of real shop data.

The immutable Play application ID/branding, Play Console ownership, upload key,
crash-reporting vendor, CI, multi-Shop policy, and password-recovery flow do not
block this controlled pilot. They must be resolved in their deferred tasks
before the applicable broader release.
