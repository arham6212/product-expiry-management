# Product Specification

## Product intent

Product Expiry Management helps small shops, groceries, minimarts, pharmacies,
restaurants, and similar businesses act before stock expires. It should reduce
expired stock, forgotten products, avoidable waste, manual checking, and missed
supplier-return opportunities.

The operating principle is: **scan once, enter as little as possible, and let
the system continuously tell the shop what needs attention.**

## Users and jobs

The initial user is a shop owner or staff member receiving and rotating stock.
Their primary jobs are:

- receive products rapidly with a barcode, expiry date, and quantity;
- see which batches require action today;
- sell or rotate stock in first-expired-first-out order;
- record what happened to expiring stock; and
- understand at-risk and lost stock value.

Multi-user roles, branches, and plan enforcement are later commercial slices.

## Non-negotiable concepts

- A product describes reusable catalog identity.
- A batch describes stock that shares an expiry date and optionally a lot code,
  supplier, or unit cost.
- Expiry belongs to the batch. Receiving the same product with a new expiry
  creates a new batch and never overwrites an existing batch.
- Inventory changes are auditable movements rather than an unexplained mutable
  number.
- Barcode primarily resolves product identity.
- OCR is assistive. Uncertain results require confirmation before persistence.

## Target workflows

### Receive stock

`Scan product -> Resolve product -> Detect expiry -> Confirm expiry -> Enter quantity -> Save batch -> Scan next`

For a known product, the normal interaction should ask only for expiry and
quantity. Structured barcodes may prefill batch/expiry fields. Product-photo
recognition is a fallback, never a mandatory step.

Resolution order:

1. shop-local catalog;
2. shared internal catalog;
3. external lookup provider;
4. manual product creation.

Suggested receiving states are `SCANNING_PRODUCT`, `RESOLVING_PRODUCT`,
`SCANNING_EXPIRY`, `CONFIRMING_EXPIRY`, `ENTERING_QUANTITY`, `SAVING`,
`SCANNING_NEXT`, and `ERROR`.

### Daily action queue

The home experience answers, "What needs my attention today?" Items are
eventually prioritized by expiry urgency, quantity, stock value,
supplier-return opportunity, and expired status. This is an action queue, not
merely an inventory list.

### Resolve expiring stock

The system supports typed outcomes: `SOLD`, `DISCOUNTED`,
`RETURNED_TO_SUPPLIER`, `DISPOSED`, and `KEPT`. Quantity-changing outcomes also
produce inventory movements.

## Expiry interpretation

Recognition may provide a candidate date, detected type (`EXP`, `USE_BY`,
`BEST_BEFORE`, `MFG`, or `UNKNOWN`), confidence, and raw text. A manufacturing
date must not be treated as expiry without a separately specified deterministic
rule. Low-confidence or ambiguous results are never silently saved.

Initial risk categories are `EXPIRED`, `TODAY`, `WITHIN_3_DAYS`,
`WITHIN_7_DAYS`, `WITHIN_30_DAYS`, and `SAFE`. Threshold semantics will be
implemented and locked by tests in the Expiry Engine slice.

## UX principles

- Minimize typing and optimize for scanner-first, one-handed use.
- Use large tap targets and a fast save-and-scan-next loop.
- Do not require a product photo.
- Surface exceptions and actions instead of every inventory row.
- Make loading, success, empty, offline, and error states explicit.
- Never silently change critical inventory data.
- Preserve entered data across recoverable network or provider failures.

## Failure behavior

- **Lookup unavailable:** search local data, then allow retry or manual product
  entry while preserving the barcode.
- **OCR unavailable:** preserve the image/draft where safe and offer manual date
  entry.
- **Connection lost while receiving:** retain the draft locally and queue a
  clearly marked save when offline persistence exists.
- **Save failure:** keep all entered data and expose retry/cancel.
- **Duplicate submission:** use an idempotency key and server transaction so a
  retry cannot double-receive inventory.

## Current phase scope

Phase 0 provides documentation, project structure, environment handling, app
shell, logging/error foundations, initial domain contracts, and tests. It does
not implement persistence, scanning, OCR, notifications, suppliers, analytics,
subscriptions, multi-user access, or multi-branch support.

