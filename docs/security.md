# Security and RLS

## Trust boundaries

The Flutter client is untrusted. A selected shop, hidden widget, local clock, or
customer search filter is never authorization. PostgreSQL grants, row-level
security, composite foreign keys, checks, triggers, and narrowly granted RPCs
remain authoritative.

## Private Shop Operations data

Anonymous users have no grants on `shops`, `shop_memberships`, `products`,
`product_barcodes`, `batches`, `inventory_movements`, invites, join requests, or
global-catalog curation tables. Authenticated inventory reads remain scoped by
membership. Batch and movement mutation remains behind the receiving RPC.
Authenticated members retain read access to their private Shop row, but direct
updates to its name, time zone, currency, or other row fields require an
`owner` membership for that same Shop. Managers, workers, anonymous users, and
members of another Shop cannot update it. Public storefront profile settings
remain a separate publication boundary with their existing permissions.

Authenticated clients have no direct membership mutation grant. Operational
role changes use only `update_shop_member_role`: a narrowly granted
`SECURITY DEFINER` function with an empty `search_path`, explicit same-shop
owner authorization, and a locked target membership. It accepts only `manager`
or `worker` and rejects self-demotion, any owner mutation, cross-Shop targets,
invalid roles, and anonymous callers. Ownership transfer remains unsupported.

## Customer publication data

Only the dedicated publication tables are customer-readable through RLS:

- `public_shop_profiles`: enabled rows only;
- `published_product_listings`: published rows whose profile is enabled; and
- `deals`: enabled rows whose listing/profile are public and whose half-open
  window contains PostgreSQL `now()`.

These rows contain no member identity, expiry, stock quantity, movement,
supplier, cost, margin, notes, or private Shop configuration. Foreign keys to
private Product rows do not grant customers access to those rows. The public
listing view also omits the internal `product_id`; customers use the public
listing ID while the same-shop Product link remains in the management base
table.

The customer client reads `public_storefront_shops`,
`public_storefront_listings`, and `public_storefront_deals` security-invoker
views. Their unconditional publication/time predicates prevent a signed-in
owner or manager from seeing draft rows through the customer UI even though
that role may read the same shop's base draft rows in management mode.

Anonymous and ordinary authenticated customers have SELECT only and no matching
write policies. Owners and managers can select draft rows and insert/update rows
only for their membership shop. Workers have no management policy. Composite
foreign keys prevent cross-shop Product/listing/deal references.

## Deals

The database—not the device—decides active visibility. Trigger validation also
serializes one listing's deal changes, rejects overlapping enabled windows,
requires offer price below listing price, and prevents a listing price change
that would invalidate an enabled offer.

## Known limitations

- Public image URLs are remote HTTP(S) references; managed upload/storage and
  moderation are not implemented.
- Public prices do not promise availability because inventory quantities are
  intentionally private.
- CatalogProduct curation/matching has no client workflow yet. Existing Products
  remain unlinked rather than accepting a guessed global match.
