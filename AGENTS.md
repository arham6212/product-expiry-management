# Product Expiry Management Agent Guide

This file contains permanent repository rules for Codex agents. Product and
architecture details live in `docs/`; task-specific state lives in `agent/`.

## Required reading

Before changing code:

1. Read `agent/current-task.md` and `agent/acceptance-criteria.md`.
2. Read the relevant files under `docs/`, especially `domain-model.md` for
   domain changes and `architecture.md` for boundary changes.
3. Inspect the existing code and tests that the task touches.

## Permanent domain rules

1. Expiry belongs to `Batch`, never to `Product`.
2. One `Product` may have multiple active `Batch` records.
3. A barcode identifies a product; it identifies a batch only when a
   structured code explicitly carries batch data.
4. Never replace an existing batch's expiry when receiving new stock. Create a
   new batch unless an explicitly specified deduplication rule proves the batch
   is the same.
5. OCR results and parsed dates are suggestions until validated.
6. Never silently persist a low-confidence expiry candidate.
7. Inventory-changing operations require an auditable `InventoryMovement`.
8. Known rules belong in deterministic domain/application services, not LLM
   prompts or UI widgets.
9. Important business rules require tests.

## Scope and implementation rules

1. Work on one small, reviewable vertical slice at a time.
2. Do not expand scope without explicit instruction.
3. Business rules must never live only in UI components.
4. Avoid unrelated refactoring.
5. Do not add a dependency without recording why it is needed and why the
   platform/library APIs are insufficient.
6. Keep domain code independent of Flutter and provider SDKs.
7. Put external integrations behind the smallest useful interface; do not add
   abstractions without an actual boundary.
8. Prefer deterministic logic when rules are known.
9. Record architectural decisions in `docs/decisions.md`.
10. Do not weaken validation merely to make tests pass.
11. Do not delete or replace working behavior without documenting why.
12. Data migrations must be explicit, reversible where practical, and safe for
    existing inventory data.
13. Preserve user changes in a dirty worktree and avoid destructive commands.
14. Run relevant tests before marking work complete.

## Development workflow

Use this sequence for every slice:

`Planner -> Implementer -> Reviewer -> Fixer -> Verification -> Commit`

The roles are stages, not necessarily separate people or agents.

### Planner

- Read the current task and inspect existing code.
- Identify affected domain rules, exact changes, edge cases, and tests.
- Update the task plan when the scope changes.
- Do not modify application code during the planning stage.

### Implementer

- Implement only the approved scope.
- Add or update tests with the behavior.
- Run focused tests and update `agent/implementation-notes.md`.

### Reviewer

- Independently inspect the complete diff.
- Compare it with every acceptance criterion and relevant domain rule.
- Classify real findings as `BLOCKER`, `HIGH`, `MEDIUM`, or `LOW`.
- Record them in `agent/review-findings.md`; do not manufacture findings.

### Fixer

- Fix confirmed findings only.
- Avoid opportunistic refactors and rerun affected tests.

### Verification

- Verify every acceptance criterion.
- Run unit and integration tests where relevant, then formatting checks,
  static analysis/type checking, and a build.
- Report each command as `PASS` or `FAIL` with any material caveat.

### Commit

- Commit only after verification, when the user has requested or authorized a
  commit.
- Keep the commit limited to the vertical slice.

## Stop conditions

Stop and report instead of guessing when a task requires:

- a destructive database migration;
- resolution of conflicting product requirements;
- a breaking API change;
- an authentication or security architecture change;
- deletion of existing functionality;
- a significant schema redesign outside the task;
- interpretation of an ambiguous rule that could corrupt inventory; or
- pricing or billing behavior without a specification.

Sensitive or destructive changes always require review. Ordinary, reversible
implementation choices within the approved slice do not require extra approval.

## Completion report

Every completed task must report:

- files changed;
- tests and verification commands run, with results;
- important decisions;
- known limitations; and
- the recommended next vertical slice.

