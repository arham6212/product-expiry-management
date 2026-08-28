# Review Findings

## Resolved

- **LOW:** `API_BASE_URL` accepted URI schemes unsuitable for API calls. Fixed by
  requiring an absolute HTTP(S) URI with authority and adding a regression test.
- **LOW:** `ExpiryRiskService` was described but not represented in the initial
  domain contracts. Added the provider-independent contract and categories;
  deterministic implementation remains correctly deferred to Phase 2.

## Open

None.
