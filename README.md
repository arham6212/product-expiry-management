# Product Expiry Management

A scanner-first expiry-date and inventory-action application for small retail
shops. The repository is currently at **Phase 0: Foundation**; product workflows
are deliberately not implemented yet.

## Foundation

- Flutter client shell for Android, iOS, and web.
- Pure Dart domain records where expiry belongs to `Batch`, not `Product`.
- Typed inventory movements and external-provider ports.
- Compile-time environment configuration with centralized logging/error hooks.
- Agent workflow and product/architecture/test documentation.

Start with [AGENTS.md](AGENTS.md), [product specification](docs/product-spec.md),
and [architecture](docs/architecture.md) before changing code.

## Run locally

```sh
flutter pub get
flutter run --dart-define-from-file=config/env.example.json
```

Compile-time values are public client configuration, not secrets. Copy the
example to an ignored `config/env.development.json` for local values; never put
private service keys into a Flutter build.

Supported keys:

- `APP_ENV`: `development`, `staging`, or `production`.
- `API_BASE_URL`: optional absolute API URL; intentionally empty in Phase 0.

## Verify

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --dart-define-from-file=config/env.example.json
```

The exact next recommended slice is manual product and batch receiving with an
atomic `RECEIVED` movement, as specified in `docs/roadmap.md`.
