# Product Specification

## Product intent

Product Expiry Management has two surfaces. Shop Operations helps small shops,
groceries, minimarts, pharmacies, restaurants, and similar businesses act before
stock expires. The Customer Marketplace lets anyone discover enabled shops and
browse products, prices, and current deals that a shop explicitly publishes.

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

### Explore a public storefront

`Explore shops -> Open storefront -> Search products -> See price/deal -> Open details`

Browsing does not require sign-in or membership. A storefront is opt-in, each
listing is opt-in, and active offers are filtered by server time. The public
surface never derives availability or promotion from private stock or expiry.

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

The current application includes authenticated, shop-owned Product resolution,
stock receiving, and owner-approved worker access. Owners share a current
six-character invite as text or a QR. Workers may enter the code manually or
scan it; both paths require explicit confirmation and create the same pending
join request for owner review.

Continuing from a resolved Product opens a minimal receiving form for a required
positive quantity and validated expiry date plus an optional lot number. One authenticated
PostgreSQL operation atomically creates the shop-owned Batch and its initial
`RECEIVED` movement. Exact retries are idempotent, conflicting key reuse is
rejected, and the entered draft survives recoverable failures.

Movement history remains the inventory source of truth; the Batch quantity is
only its transactionally initialized query projection. New manual receiving
rejects a missing expiry, while existing historical rows with unknown expiry
remain nullable and are never assigned invented dates. Product resolution
accepts camera or typed barcodes, checks the selected shop first, caches usable
Open Food Facts results, and offers manual Product creation without inventing
an unknown Product after provider failure. The catalog repository can also
create a normalized shop-owned Product without a barcode. Receiving exposes
that minimal name/optional-brand action, selects the persisted Product, and
retains the dated Batch draft so the worker can continue directly.
OCR, offline outbox, notifications, suppliers, analytics, subscriptions,
advanced role administration, and multi-branch administration remain out of
scope.

The application also preserves the first customer storefront slice behind the
static `ENABLE_STOREFRONT` build define. It defaults to disabled for the pilot,
which opens Shop Operations directly and hides storefront navigation so the
optional schema is not required. When explicitly enabled, anonymous customers
start in Explore and can open an enabled shop, search its published Products,
see selling prices and currently active deals, and open Product details. Shop
Operations remains behind the existing authentication and active shop gate.
Owners and managers can configure the public profile, publish or unpublish
existing shop Products, set prices, and manage time-bounded deals; workers
cannot. There is no ordering, payment, stock-availability promise, or automatic
expiry promotion.

This section describes the repository as inspected, not the Android pilot exit
criteria. The pilot requires expiry on every new manual receive while preserving
existing nullable rows safely. The implementation sequence is specified in
`docs/release-plan.md`.
