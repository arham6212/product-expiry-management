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
flutter run --dart-define-from-file=config/env.local.json
```

Compile-time values are public client configuration, not secrets. Copy
`config/env.example.json` to the ignored `config/env.local.json` and provide the
project's client-safe values. Never put private service keys into a Flutter
build.

Supported keys:

- `APP_ENV`: `development`, `staging`, or `production`.
- `API_BASE_URL`: optional absolute API URL; intentionally empty in Phase 0.
- `ENABLE_STOREFRONT`: optional strict `true`/`false`; defaults to `false` so
  releases do not require the optional storefront schema.
- `SUPABASE_URL`: required absolute HTTP(S) Supabase project URL.
- `SUPABASE_PUBLISHABLE_KEY`: required client-safe Supabase publishable key.

With the default storefront setting, the app opens directly in authenticated
Shop Operations and hides storefront browsing/management navigation. Set
`ENABLE_STOREFRONT` to `true` only for a build whose storefront migration has
been reviewed and deployed; that preserves Explore as the root surface.

## Verify

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --dart-define-from-file=config/env.local.json
```

The audited Android pilot plan and exact next slice are in
[`docs/release-plan.md`](docs/release-plan.md). Batch receiving is implemented;
the expiry dashboard, resolution, notifications, and release configuration are
not yet pilot-ready.
