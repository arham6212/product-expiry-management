# Acceptance Criteria

- Only `authenticated` receives execute permission on
  `update_shop_member_role(uuid, uuid, text)`; public and anon do not.
- The security-definer function pins an empty search path, resolves `auth.uid()`,
  authorizes a same-shop owner, and locks the exact target membership.
- A same-shop owner can change worker to manager and manager to worker.
- Manager, worker, anonymous, and cross-Shop callers are rejected without a
  write; a caller cannot target a Shop they do not own.
- Only exact `manager` and `worker` values are accepted. Unknown/null values and
  promotion to owner are rejected rather than coerced.
- Self-demotion and attempts to alter any owner membership are rejected without
  changing the row.
- Membership Shop/user identity and row count are preserved; direct client
  membership updates remain unavailable.
- Existing member roster reads, invites, join behavior, B05 Shop settings RLS,
  and unrelated Product/inventory/storefront behavior remain unchanged.
- No Flutter production code changes because role controls are explicitly B07.
- The migration and 29-assertion pgTAP suite must pass before B06 is complete;
  otherwise it remains verification-pending.
