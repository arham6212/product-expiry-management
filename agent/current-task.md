# Current Task

## Objective

Execute `B06 — Add an owner-only member-role RPC` from `docs/release-plan.md`
while preserving B01–B05 work and task states.

## Approved scope

- Add one narrowly granted, security-definer role-update RPC.
- Authorize only a same-shop owner, lock the target membership, and allow only
  manager/worker transitions without ownership or tenant changes.
- Add focused pgTAP coverage for grants, allowed transitions, every caller role,
  cross-Shop targets, owner invariants, direct-mutation denial, and regressions.
- Add a safe recovery script and document that persisted role changes are not
  automatically guessed or reversed.

## Out of scope

- B07 or any other release-plan task.
- Flutter repository/controller/Team & Access role controls, ownership
  transfer, member removal, custom permissions, or membership redesign.
- Invite/join behavior, RLS broadening, migration deployment, or commits.
- Reopening or altering B01–B05 implementation.

## Status

Implementation complete on 2026-09-03; verification pending because local
Supabase/PostgreSQL is unavailable for the required migration and pgTAP run.
B01 and B04 remain complete; B02, B03, and B05 remain
implementation-complete/verification-pending.
