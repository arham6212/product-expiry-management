# Product Expiry Management

A two-surface retail application: scanner-first expiry/inventory operations for
shop teams and an anonymous customer marketplace for explicitly published shop
Products, prices, and deals.

## Current foundation

- Flutter client shell for Android, iOS, and web.
- Pure Dart domain records where expiry belongs to `Batch`, not `Product`.
- Typed inventory movements and external-provider ports.
- Compile-time environment configuration with centralized logging/error hooks.
- Agent workflow and product/architecture/test documentation.
- Anonymous public shop discovery with database-enforced publication privacy.
- Owner/manager storefront, listing, price, and deal management.

Start with [AGENTS.md](AGENTS.md), [product specification](docs/product-spec.md),
and [architecture](docs/architecture.md) before changing code.

## Run locally

```sh
flutter pub get
flutter run --dart-define-from-file=config/env.development.local.json
```

Compile-time values are public client configuration, not secrets. Copy
`config/env.example.json` to the ignored `config/env.development.local.json` or
`config/env.staging.local.json`, set the matching explicit `APP_ENV`, and provide
the project's client-safe values. Never put private service keys into a Flutter
build.

Supported keys:

- `APP_ENV`: required; `development`, `staging`, or `production`.
- `API_BASE_URL`: optional absolute API URL; intentionally empty in Phase 0.
- `ENABLE_STOREFRONT`: strict `true`/`false`; production requires an explicit
  value and the pilot value is `false`.
- `STOREFRONT_SCHEMA_AVAILABLE`: set to `true` only after the storefront schema
  is intentionally verified; production rejects unsafe storefront enablement.
- `SUPABASE_URL`: required absolute HTTP(S) Supabase project URL.
- `SUPABASE_PUBLISHABLE_KEY`: required client-safe Supabase publishable key.
- `PRODUCTION_SUPABASE_PROJECT_REF`: required for production and must match the
  project hostname, preventing an accidental development-project build.

With the default storefront setting, the app opens directly in authenticated
Shop Operations and hides storefront browsing/management navigation. Set
`ENABLE_STOREFRONT` to `true` only for a build whose storefront migration has
been reviewed and deployed, and set `STOREFRONT_SCHEMA_AVAILABLE=true`; that
preserves Explore as the root surface.

For the pilot release, create the ignored
`config/env.production.local.json` with approved public values, then validate
and build through the preflight wrapper:

```sh
dart run tool/build_pilot_apk.dart --check config/env.production.local.json
dart run tool/build_pilot_apk.dart config/env.production.local.json
```

The wrapper rejects missing or non-production configuration before starting
Flutter/Gradle. Never place a service-role or secret key in this file.

## Verify

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --dart-define-from-file=config/env.local.json
```

The audited Android pilot plan and exact next slice are in
[`docs/release-plan.md`](docs/release-plan.md). Batch receiving is implemented;
Batch resolution and notifications are not yet pilot-ready.
