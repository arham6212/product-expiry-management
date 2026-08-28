# Acceptance Criteria

## Feature: Phase 0 repository foundation

Given:

- The repository contains the default Flutter scaffold.

When:

- The Phase 0 foundation is completed.

Then:

- `AGENTS.md` defines permanent rules, workflow roles, stop conditions, and the
  completion report.
- Product, architecture, domain, roadmap, decision, and testing documents exist
  and agree on the batch-expiry rule.
- The app starts in a branded shell with working base navigation and a simple
  action-oriented home placeholder.
- Environment values are read without committing secrets.
- Unhandled Flutter and asynchronous errors use centralized logging hooks.
- Initial domain types represent the required entities and provider boundaries
  without depending on Flutter/vendor SDKs.
- Formatting, static analysis/type checking, unit/widget tests, and a target
  build pass.
- No out-of-scope product feature or vendor SDK is implemented.

## Feature: Multiple expiry batches remain independent

Given:

- A product exists.
- An existing batch expires on 2026-09-03.

When:

- A second batch is represented for that product with expiry 2026-09-12.

Then:

- The product identity is reused.
- The original batch still expires on 2026-09-03.
- The new batch expires on 2026-09-12.
- Expiry is not stored on the product.

## Template for the next slice

Feature: `<one observable outcome>`

Given:

- `<initial state>`

When:

- `<action>`

Then:

- `<observable result>`
- `<domain/persistence result>`
- `<important unchanged state>`

