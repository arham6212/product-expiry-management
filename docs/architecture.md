# Architecture

## Chosen stack

| Concern | Choice | Reasoning |
| --- | --- | --- |
| Client | Flutter/Dart for Android, iOS, and web | The repository already uses Flutter; one typed codebase supports camera-led mobile workflows and a web admin surface. |
| Client structure | Feature-first presentation/application layers with a provider-independent pure Dart domain | Keeps business rules testable without widgets or SDKs and lets slices remain local. |
| Client state | Riverpod providers and Notifier/AsyncNotifier controllers | Centralizes reactive workflow state and dependency overrides while keeping Flutter, Riverpod, and mutable UI resources outside the domain and data contracts. |
| Backend/API | Supabase APIs plus narrowly scoped server/edge functions where transactions or secrets require them | A small team gets authentication, PostgreSQL, storage, and realtime primitives without operating a bespoke service. Domain ports prevent direct coupling. |
| Database | Managed PostgreSQL | Relational constraints and transactions fit products, batches, movements, actions, and shop ownership. |
| Authentication | Supabase Auth email/password with shop-membership RLS | Supplies `auth.uid()` to PostgreSQL policies without putting privileged credentials in the client. |
| Offline | Online-first V1 with explicit loading/error/retry and server idempotency; a local outbox is post-release | Releases the core value sooner without pretending a partial cache is full synchronization. |
| Barcode | `mobile_scanner` UI adapter with normalization/deduplication in Riverpod application state | Camera SDK details stay outside resolution and persistence rules. |
| Product lookup | Shop-owned Supabase catalog, then Open Food Facts behind `ProductLookupProvider` | Enforces database-first resolution and persistently caches normalized external hits without coupling provider data to widgets/domain. |
| Expiry OCR | On-device recognition when practical, optional remote adapter behind `ExpiryRecognitionProvider` | Supports latency/offline goals and avoids coupling persisted data to one OCR vendor. |
| Notifications | Local scheduling behind `NotificationProvider` for V1; push is post-release | Supports on-device reminders without coupling expiry rules to one delivery system. |
| Analytics/crashes | Privacy-conscious product events and crash reporting selected in a dedicated observability slice | Avoids leaking barcode/OCR/inventory data before consent and redaction rules exist. |
| Tests | `flutter_test`/Dart unit and widget tests; repository integration tests; device E2E later | Uses the standard toolchain and adds heavier layers only when the behavior exists. |
| Deployment | Mobile store builds and static Flutter web; managed backend migrations through CI | Separates client releases from explicit, reviewed database changes. |

These are direction-setting choices reconciled with the current repository.
Installed SDK dependencies are listed in `pubspec.yaml`; every additional SDK
still needs slice-specific justification and an ADR if it changes a boundary.

## Code boundaries

```text
lib/
  app/                 composition root, theme, navigation shell
  core/                environment, errors, logging, cross-cutting utilities
  domain/
    entities/          provider- and Flutter-independent domain records
    value_objects/     validated domain primitives
    ports/             small contracts for external capabilities
    services/          deterministic business-rule contracts/implementations
  features/<feature>/
    application/       use cases and state orchestration (when needed)
    data/              repositories, DTOs, adapters (when needed)
    presentation/      screens and widgets
```

Dependencies point inward: presentation/data may depend on application/domain;
domain never imports Flutter, database, camera, network, or vendor packages.
Features should expose only what the app composition root needs.

## Runtime shape

The Flutter composition root loads compile-time configuration, installs global
framework/async error hooks, constructs feature dependencies, and installs one
Riverpod `ProviderScope`. Existing dependency instances are supplied through
overrides; widgets observe application controllers and call application use
cases. Use cases transact through repository ports. External-provider adapters
translate external data into explicit domain values and failures.

The composition root initializes the Supabase Flutter client from the
compile-time project URL and publishable key before mounting the widget tree.
`ENABLE_STOREFRONT` is a strict static build define that defaults to `false`.
Disabled builds open the existing authentication/shop gate directly and omit
storefront browsing and management navigation, so the optional storefront
schema is not queried. When the flag is explicitly `true`, the root customer
surface is the anonymous-capable Explore screen and Shop Operations remains
reachable through the same gate. The gate signs the user in, loads only
memberships visible through RLS, and derives one explicit active shop from the
Riverpod shop session. One shop is selected automatically; multiple memberships
require a user choice; a user with none can call the constrained first-shop RPC.
The shop session depends on authenticated user identity, suppresses same-user
token refresh events, and clears when that identity ends or changes.

Riverpod owns auth action feedback, shop loading/selection, shell navigation,
Product-resolution progress/results, and receiving load/submission/retry state.
Separate public-storefront providers load public shop IDs supplied by customer
navigation and never depend on active-shop state. Storefront-management
providers do depend on the active shop and reject workers before loading.
The Product resolver and receiving controller continue to receive `shopId`
explicitly. `ConsumerStatefulWidget` is used only for disposable Flutter-owned
resources such as text controllers and form keys; workflow state does not use
widget `setState`. Domain entities, ports, use cases, and Supabase adapters do
not import Riverpod. Product-resolution and manual-save controllers capture the
active shop at request start and discard any returned Product if that shop is no
longer active, preventing stale asynchronous work from crossing shop sessions.

Product/barcode persistence is Supabase-backed. UI calls
`ResolveProductByBarcode`, which receives the selected shop ID, queries the
shop-local barcode mapping first, and calls `ProductLookupProvider` only on a
miss. Open Food Facts responses are normalized into domain metadata before an
atomic database RPC creates Product plus ProductBarcode. Camera and typed
barcode entry feed that same Riverpod workflow. A provider miss or failure can
open manual Product entry with the barcode preserved; manual persistence uses a
second narrow RPC that delegates to the same shop/barcode lock and returns any
concurrent winner.

Receiving is also Supabase-backed in production. The resolved Product and
selected shop flow into `ReceiveStock`, then `InventoryRepository`, then the
`receive_product_stock` RPC. The RPC is the authoritative transaction and
idempotency boundary: it verifies the caller and membership, verifies that the
Product belongs to the supplied shop, and creates the Batch plus initial
`RECEIVED` movement together. Tests and demo composition retain the in-memory
adapter.

### Shop ownership and product catalog boundary

`auth.users` is identity. `shops` is the tenant and `shop_memberships` is the
only membership link. PostgreSQL RLS checks `auth.uid()` membership for every
shop-owned product/barcode operation; `anon` has no grants. The client never
derives authorization from its selected shop alone—the explicit shop ID scopes
queries, while RLS independently authorizes it.

`product_barcodes` has `UNIQUE (shop_id, barcode)` and a composite foreign key
to `(products.shop_id, products.id)`. The external-save RPC takes a transaction
advisory lock for that shop/code, rechecks the mapping, and creates both records
or returns the winner. Manual entry delegates to that RPC before marking a newly
created Product as `local_manual`, so manual/external races share the same lock.
This prevents concurrent cache misses from creating two products for one shop
barcode.

The catalog repository also exposes one explicit barcode-less manual creation
operation. It normalizes required name and optional brand metadata, inserts a
shop-owned `local_manual` Product through the existing member-scoped RLS policy,
and creates neither a `product_barcodes` row nor a platform catalog identity. A
feature-scoped Riverpod notifier captures the active shop while saving; the
minimal receiving action returns the persisted Product, adds and selects it in
the existing receiving state, and leaves quantity, expiry, and lot controls
untouched.

### Public storefront boundary

The deployed `products` table remains the shop-owned Product used by barcode,
Batch, and movement workflows. A new optional `catalog_product_id` points toward
the separate platform-wide `catalog_products` identity; existing Products are
left unlinked because safe global deduplication is not yet specified.

Customer publication uses three dedicated tables plus filtered customer views:

```text
shops (private tenant)
  -> public_shop_profiles (explicit enabled storefront)
    -> published_product_listings (explicit Product publication + price)
      -> deals (time-bounded offer)

catalog_products (global identity)
  <- products.catalog_product_id (optional shop-owned relationship)
  -> products -> batches -> inventory_movements
```

`published_product_listings` references `(shop_id, product_id)` with a composite
foreign key but copies only intentionally public presentation fields. The
customer view omits the internal Product ID and exposes the listing ID instead. Customers
receive no grant on `shops`, `products`, barcodes, batches, movements,
memberships, or global-catalog curation tables. Public RLS exposes only enabled
profiles, published listings in enabled profiles, and enabled deals whose
half-open time window contains PostgreSQL `now()`. The customer repository reads
security-invoker `public_storefront_*` views that repeat these filters, so an
owner's broader management SELECT policy cannot make drafts appear in Explore.
Owners and managers can read draft base rows and mutate only their shop; workers
cannot manage publication.
Enabled deal windows for one listing cannot overlap, and database triggers keep
offer prices below the listing price.

PostgreSQL row-level security scopes Batch and movement reads by shop
membership. Flutter has no direct mutation grants for either table; the
authenticated RPC is narrowly granted and uses a pinned empty search path plus
schema-qualified names. The function takes a transaction advisory lock keyed
by `(shop_id, idempotency_key)` and the movement table independently enforces
that pair as unique. Exact retries with the same Product, quantity, required
expiry, and normalized lot return the original records. Changed input under the
same key is rejected and writes nothing.

The in-memory adapter mirrors this contract for deterministic tests by staging
complete replacement collections before publishing. It is not used for
receiving in production composition.

### Shop invitation boundary

Owners manage one current, time-bounded invite through `ShopMembersController`.
The repository reads the active, unexpired invite through an owner-only function
that uses server time, and rotation immediately replaces the Riverpod state that
supplies the rendered QR. PostgreSQL enforces a
partial unique index so a shop cannot have two active invite rows. Owner-only
RPCs serialize enable/disable and rotation; rotation revokes every older code.

Manual entry and camera scanning are two transports for the same six-character
code. `ShopInviteQr` owns normalization and the application payload
`shop-invite:<CODE>`. An auto-disposed Riverpod scanner controller rejects
malformed input and duplicate callbacks. The scanner route returns the code to
the no-shop join form, where the user must explicitly confirm. Only then does
`ShopSessionController.requestToJoinShop(code)` call the existing repository and
`request_to_join_shop` RPC. The RPC—not QR parsing—authoritatively checks
authentication, membership, duplicate pending requests, active/revoked state,
and expiry.

## Data and synchronization principles

- Store expiry as a calendar date, not an instant; shop timezone is used when
  comparing it with "today."
- Store timestamps as UTC instants and render them in the shop timezone.
- All shop-owned rows carry `shop_id` even when ownership could be reached by a
  join, making authorization and querying explicit.
- Every remote mutation has a client-generated idempotency key.
- A manual receive quantity is currently limited to the portable signed 32-bit
  domain `1..2,147,483,647`; the application validates this before persistence.
- A local receiving draft is not shown as saved until the server acknowledges
  it. Retrying uses the same key.
- Conflicts that alter quantity or expiry are surfaced; last-write-wins is not
  acceptable for critical inventory fields.
- Logs contain identifiers and error categories, not OCR images, recognized raw
  text, credentials, or personal details by default.

## External provider contracts

- `BarcodeScanner` emits scan observations; it does not resolve products.
- `ProductLookupProvider` returns provider-neutral product candidates.
- `ExpiryRecognitionProvider` returns candidates with raw text, date type, and
  confidence; it does not persist or auto-confirm them.
- `NotificationProvider` schedules/cancels typed notification requests.

Adapters are chosen when a vertical slice needs them. Ports should remain small
and grow from demonstrated use cases rather than anticipated vendor APIs.

## Error handling

Domain validation failures are typed and recoverable. Infrastructure adapters
translate SDK/network failures into application failures. The composition root
captures uncaught Flutter and asynchronous errors through `AppLogger`; a future
crash adapter can be added there. User-facing messages must be actionable and
must not expose stack traces or secrets.

## Security and privacy baseline

- No service-role or provider secrets ship in the client.
- Client configuration supplied by `--dart-define` is considered public.
- Anonymous users have read-only grants only on the dedicated storefront
  profile/listing/deal tables, constrained by RLS. They have no inventory,
  membership, private-shop, or catalog-curation grants.
- Authorization is enforced server-side with `auth.uid()`, role-aware
  memberships, row-level policies, server time, and cross-shop foreign keys.
- Private `shops` rows remain readable by members for operations, while their
  tenant name/time-zone/currency configuration is directly updatable only by a
  same-shop owner. Storefront profile management remains a separate boundary.
- Membership rows have no direct client mutation grant. Operational role
  changes are serialized through the narrowly granted, empty-search-path
  `update_shop_member_role` function, which authorizes a same-shop owner and
  locks the exact target membership before allowing only manager/worker changes.
  Riverpod-based Team & Access integration remains the separate B07 slice.
- Camera images and OCR text have explicit retention rules before upload.
- Destructive operations and data migrations require review under `AGENTS.md`.
