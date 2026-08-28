# Architecture

## Chosen stack

| Concern | Choice | Reasoning |
| --- | --- | --- |
| Client | Flutter/Dart for Android, iOS, and web | The repository already uses Flutter; one typed codebase supports camera-led mobile workflows and a web admin surface. |
| Client structure | Feature-first presentation/application layers with a provider-independent pure Dart domain | Keeps business rules testable without widgets or SDKs and lets slices remain local. |
| Backend/API | Supabase APIs plus narrowly scoped server/edge functions where transactions or secrets require them | A small team gets authentication, PostgreSQL, storage, and realtime primitives without operating a bespoke service. Domain ports prevent direct coupling. |
| Database | Managed PostgreSQL | Relational constraints and transactions fit products, batches, movements, actions, and shop ownership. |
| Authentication | Supabase Auth, introduced with the first authenticated persistence slice | Integrates with row-level security; Phase 0 avoids a fake auth layer. |
| Offline | Local SQLite through Drift, with an outbox and idempotency keys in a future receiving slice | Receiving must tolerate unstable networks; explicit synchronization is safer than pretending every call is online. |
| Barcode | Camera scanner adapter (likely `mobile_scanner`) behind `BarcodeScanner` | Scanner SDK details do not enter workflow/domain logic. Exact dependency is chosen in its slice. |
| Product lookup | Local repository, shared catalog, then external provider adapters behind `ProductLookupProvider` | Encodes the required resolution order while keeping external databases replaceable. |
| Expiry OCR | On-device recognition when practical, optional remote adapter behind `ExpiryRecognitionProvider` | Supports latency/offline goals and avoids coupling persisted data to one OCR vendor. |
| Notifications | Local scheduling plus FCM/APNs through `NotificationProvider` | Supports on-device reminders initially and push delivery later. |
| Analytics/crashes | Privacy-conscious product events and crash reporting selected in a dedicated observability slice | Avoids leaking barcode/OCR/inventory data before consent and redaction rules exist. |
| Tests | `flutter_test`/Dart unit and widget tests; repository integration tests; device E2E later | Uses the standard toolchain and adds heavier layers only when the behavior exists. |
| Deployment | Mobile store builds and static Flutter web; managed backend migrations through CI | Separates client releases from explicit, reviewed database changes. |

These are direction-setting choices. Only Flutter/Dart and its standard testing
tooling are installed in Phase 0. Every additional SDK needs slice-specific
justification and an ADR if it changes a boundary.

## Code boundaries

```text
lib/
  app/                 composition root, theme, navigation shell
  core/                environment, errors, logging, cross-cutting utilities
  domain/
    entities/          provider- and Flutter-independent domain records
    value_objects/     validated domain primitives
    ports/             small contracts for external capabilities
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
framework/async error hooks, and constructs feature dependencies. UI calls
application use cases. Use cases transact through repository ports. Provider
adapters translate external data into explicit domain values and failures.

The future backend is the authoritative shared state. PostgreSQL row-level
security scopes records by shop membership. Critical receiving writes create a
batch and its initial `RECEIVED` movement in one transaction using a unique
idempotency key. Cached `Batch.currentQuantity` may be maintained transactionally
for fast reads and reconciled against movements.

## Data and synchronization principles

- Store expiry as a calendar date, not an instant; shop timezone is used when
  comparing it with "today."
- Store timestamps as UTC instants and render them in the shop timezone.
- All shop-owned rows carry `shop_id` even when ownership could be reached by a
  join, making authorization and querying explicit.
- Every remote mutation has a client-generated idempotency key.
- A local receiving draft is not shown as synced until the server acknowledges
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
- Authorization is enforced server-side with membership and row-level policies.
- Camera images and OCR text have explicit retention rules before upload.
- Destructive operations and data migrations require review under `AGENTS.md`.

