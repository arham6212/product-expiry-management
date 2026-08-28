# Test Strategy

## Principles

- Tests follow risk: inventory integrity and date boundaries get the strongest
  coverage.
- Pure business rules are unit tested without Flutter, network, clocks, locale,
  or providers unless explicitly injected.
- Integration tests use real persistence constraints where possible, not mocks
  of those constraints.
- E2E tests cover only critical user journeys and run on supported device sizes.
- Every regression test fails for the original defect before its fix.

## Test layers

### Unit tests

- date-only validation, formatting, leap years, and comparison;
- expiry risk calculations and boundary semantics;
- FEFO ordering and tie breakers;
- batch creation/deduplication rules;
- date interpretation and MFG-versus-expiry handling; and
- inventory quantity calculations and invalid quantities.

### Integration tests

- product, barcode, batch, and movement persistence;
- atomic receiving transaction;
- tenant/shop isolation and authorization rules;
- idempotent duplicate prevention and safe retries; and
- simultaneous quantity updates and reconciliation.

Use a real disposable PostgreSQL database once backend persistence exists. Local
store tests use an actual temporary SQLite database.

### Widget and E2E tests

- shell navigation and accessibility semantics;
- manual receive flow;
- known-product receive flow;
- unknown barcode flow;
- expiry confirmation/correction flow; and
- save-and-scan-next, including offline/retry states.

Camera and platform SDKs may use boundary fakes in automated tests, supplemented
by a small real-device smoke suite.

## Adversarial matrix

Required cases include:

- same barcode with multiple batches and expiries;
- yesterday, today, and every risk threshold boundary;
- February 29 in leap and non-leap years;
- malformed, ambiguous, and locale-sensitive dates;
- OCR returns MFG instead of expiry or low confidence;
- duplicate scan/submission and a retry after unknown outcome;
- zero, negative, and excessively large quantities;
- lookup/OCR offline and internet loss during save;
- simultaneous updates that would oversell stock; and
- client/server timezone disagreement around midnight.

## Verification commands

Run focused tests while implementing, then before completion:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

When integration or E2E suites exist, add their documented commands. A task is
not `PASS` when a relevant suite was skipped; report why it could not run.

## Reusable acceptance-criteria format

```text
Feature: <one observable outcome>

Given:
- <initial state or invariant>

When:
- <single action or event>

Then:
- <observable result>
- <persisted/domain result>
- <important non-result or unchanged state>
```

Criteria should use specific values at boundaries and avoid implementation
details unless an architectural constraint is itself under test.

