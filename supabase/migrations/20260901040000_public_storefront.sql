-- Add a customer-safe publication layer without changing the meaning or grants
-- of the existing shop-owned inventory tables.

create table public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null check (char_length(btrim(canonical_name)) between 1 and 240),
  brand text check (brand is null or char_length(btrim(brand)) between 1 and 240),
  image_url text check (image_url is null or image_url ~ '^https?://'),
  source text not null check (source in ('open_food_facts', 'verified_manual')),
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index catalog_products_source_reference_key
on public.catalog_products (source, source_reference)
where source_reference is not null;

create table public.catalog_product_barcodes (
  id uuid primary key default gen_random_uuid(),
  catalog_product_id uuid not null references public.catalog_products(id) on delete cascade,
  barcode text not null unique check (
    barcode ~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$'
  ),
  format text not null check (format in ('ean8', 'upc_a', 'ean13', 'gtin14', 'unknown')),
  created_at timestamptz not null default now()
);

alter table public.products
add column catalog_product_id uuid references public.catalog_products(id) on delete set null;

create index products_catalog_product_id_idx
on public.products (catalog_product_id)
where catalog_product_id is not null;

create table public.public_shop_profiles (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 120),
  description text check (description is null or char_length(btrim(description)) between 1 and 1000),
  logo_url text check (logo_url is null or logo_url ~ '^https?://'),
  area text check (area is null or char_length(btrim(area)) between 1 and 160),
  is_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.published_product_listings (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.public_shop_profiles(shop_id) on delete cascade,
  product_id uuid not null,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 240),
  description text check (description is null or char_length(btrim(description)) between 1 and 2000),
  image_url text check (image_url is null or image_url ~ '^https?://'),
  price_minor integer not null check (price_minor between 1 and 2147483647),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint published_product_listings_shop_id_id_key unique (shop_id, id),
  constraint published_product_listings_shop_product_key unique (shop_id, product_id),
  constraint published_product_listings_product_shop_fkey
    foreign key (shop_id, product_id)
    references public.products(shop_id, id)
    on delete restrict
);

create index published_product_listings_public_idx
on public.published_product_listings (shop_id, display_name)
where is_published;

create table public.deals (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  listing_id uuid not null,
  offer_price_minor integer not null check (offer_price_minor between 1 and 2147483647),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_enabled boolean not null default true,
  title text check (title is null or char_length(btrim(title)) between 1 and 160),
  description text check (description is null or char_length(btrim(description)) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deals_shop_id_id_key unique (shop_id, id),
  constraint deals_listing_shop_fkey
    foreign key (shop_id, listing_id)
    references public.published_product_listings(shop_id, id)
    on delete cascade,
  constraint deals_time_window_check check (starts_at < ends_at)
);

create index deals_listing_window_idx
on public.deals (shop_id, listing_id, starts_at, ends_at)
where is_enabled;

create trigger catalog_products_set_updated_at
before update on public.catalog_products
for each row execute function public.set_updated_at();

create trigger public_shop_profiles_set_updated_at
before update on public.public_shop_profiles
for each row execute function public.set_updated_at();

create trigger published_product_listings_set_updated_at
before update on public.published_product_listings
for each row execute function public.set_updated_at();

create trigger deals_set_updated_at
before update on public.deals
for each row execute function public.set_updated_at();

create function public.ensure_public_shop_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.public_shop_profiles (shop_id, display_name)
  values (new.id, new.name)
  on conflict (shop_id) do nothing;
  return new;
end;
$$;

insert into public.public_shop_profiles (shop_id, display_name)
select shop.id, shop.name
from public.shops as shop
on conflict (shop_id) do nothing;

create trigger shops_ensure_public_profile
after insert on public.shops
for each row execute function public.ensure_public_shop_profile();

create function public.can_manage_public_storefront(target_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = target_shop_id
        and membership.user_id = auth.uid()
        and membership.role in ('owner', 'manager')
    );
$$;

create function public.validate_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing_price integer;
begin
  if not public.can_manage_public_storefront(new.shop_id) then
    raise exception using
      errcode = '42501',
      message = 'Only an owner or manager can manage deals.';
  end if;

  if tg_op = 'UPDATE'
    and (new.shop_id, new.listing_id) is distinct from (old.shop_id, old.listing_id) then
    raise exception using
      errcode = '22023',
      message = 'A deal cannot be moved to another listing.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.shop_id::text || ':' || new.listing_id::text, 0)
  );

  select listing.price_minor
  into listing_price
  from public.published_product_listings as listing
  where listing.shop_id = new.shop_id
    and listing.id = new.listing_id;

  if listing_price is null then
    raise exception using errcode = '23503', message = 'Deal listing is unavailable.';
  end if;
  if new.offer_price_minor >= listing_price then
    raise exception using
      errcode = '22023',
      message = 'Offer price must be lower than the listing price.';
  end if;

  if new.is_enabled and exists (
    select 1
    from public.deals as existing
    where existing.shop_id = new.shop_id
      and existing.listing_id = new.listing_id
      and existing.id is distinct from new.id
      and existing.is_enabled
      and existing.starts_at < new.ends_at
      and existing.ends_at > new.starts_at
  ) then
    raise exception using
      errcode = '23P01',
      message = 'Enabled deal windows cannot overlap for one listing.';
  end if;

  return new;
end;
$$;

create trigger deals_validate
before insert or update on public.deals
for each row execute function public.validate_deal();

create function public.validate_listing_price_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.shop_id::text || ':' || new.id::text, 0)
  );

  if new.price_minor <> old.price_minor and exists (
    select 1
    from public.deals as deal
    where deal.shop_id = new.shop_id
      and deal.listing_id = new.id
      and deal.is_enabled
      and deal.offer_price_minor >= new.price_minor
  ) then
    raise exception using
      errcode = '22023',
      message = 'Listing price must remain above every enabled offer price.';
  end if;
  return new;
end;
$$;

create trigger published_product_listings_validate_price
before update of price_minor on public.published_product_listings
for each row execute function public.validate_listing_price_change();

alter table public.catalog_products enable row level security;
alter table public.catalog_product_barcodes enable row level security;
alter table public.public_shop_profiles enable row level security;
alter table public.published_product_listings enable row level security;
alter table public.deals enable row level security;

revoke all on table public.catalog_products from anon, authenticated;
revoke all on table public.catalog_product_barcodes from anon, authenticated;
revoke all on table public.public_shop_profiles from anon, authenticated;
revoke all on table public.published_product_listings from anon, authenticated;
revoke all on table public.deals from anon, authenticated;

grant select on table public.public_shop_profiles to anon, authenticated;
grant select on table public.published_product_listings to anon, authenticated;
grant select on table public.deals to anon, authenticated;
grant insert, update on table public.public_shop_profiles to authenticated;
grant insert, update on table public.published_product_listings to authenticated;
grant insert, update on table public.deals to authenticated;

create policy "Public can read enabled shop profiles"
on public.public_shop_profiles for select
to anon, authenticated
using (is_enabled);

create policy "Managers can read their shop profile"
on public.public_shop_profiles for select
to authenticated
using ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can insert their shop profile"
on public.public_shop_profiles for insert
to authenticated
with check ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can update their shop profile"
on public.public_shop_profiles for update
to authenticated
using ((select public.can_manage_public_storefront(shop_id)))
with check ((select public.can_manage_public_storefront(shop_id)));

create policy "Public can read published listings"
on public.published_product_listings for select
to anon, authenticated
using (
  is_published
  and exists (
    select 1
    from public.public_shop_profiles as profile
    where profile.shop_id = published_product_listings.shop_id
      and profile.is_enabled
  )
);

create policy "Managers can read their shop listings"
on public.published_product_listings for select
to authenticated
using ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can insert their shop listings"
on public.published_product_listings for insert
to authenticated
with check ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can update their shop listings"
on public.published_product_listings for update
to authenticated
using ((select public.can_manage_public_storefront(shop_id)))
with check ((select public.can_manage_public_storefront(shop_id)));

create policy "Public can read active deals"
on public.deals for select
to anon, authenticated
using (
  is_enabled
  and starts_at <= now()
  and ends_at > now()
  and exists (
    select 1
    from public.published_product_listings as listing
    join public.public_shop_profiles as profile
      on profile.shop_id = listing.shop_id
    where listing.shop_id = deals.shop_id
      and listing.id = deals.listing_id
      and listing.is_published
      and profile.is_enabled
  )
);

create policy "Managers can read their shop deals"
on public.deals for select
to authenticated
using ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can insert their shop deals"
on public.deals for insert
to authenticated
with check ((select public.can_manage_public_storefront(shop_id)));

create policy "Managers can update their shop deals"
on public.deals for update
to authenticated
using ((select public.can_manage_public_storefront(shop_id)))
with check ((select public.can_manage_public_storefront(shop_id)));

-- Public app reads use these unconditional projections. This prevents an
-- owner/manager's intentionally broader base-table SELECT policies from making
-- draft rows appear when that same authenticated user browses as a customer.
create view public.public_storefront_shops
with (security_invoker = true, security_barrier = true)
as
select
  profile.shop_id,
  profile.display_name,
  profile.description,
  profile.logo_url,
  profile.area,
  profile.is_enabled,
  profile.created_at,
  profile.updated_at
from public.public_shop_profiles as profile
where profile.is_enabled;

create view public.public_storefront_listings
with (security_invoker = true, security_barrier = true)
as
select
  listing.id,
  listing.shop_id,
  listing.display_name,
  listing.description,
  listing.image_url,
  listing.price_minor,
  listing.currency_code,
  listing.is_published,
  listing.created_at,
  listing.updated_at
from public.published_product_listings as listing
where listing.is_published
  and exists (
    select 1
    from public.public_shop_profiles as profile
    where profile.shop_id = listing.shop_id
      and profile.is_enabled
  );

create view public.public_storefront_deals
with (security_invoker = true, security_barrier = true)
as
select
  deal.id,
  deal.shop_id,
  deal.listing_id,
  deal.offer_price_minor,
  deal.starts_at,
  deal.ends_at,
  deal.is_enabled,
  deal.title,
  deal.description,
  deal.created_at,
  deal.updated_at
from public.deals as deal
where deal.is_enabled
  and deal.starts_at <= now()
  and deal.ends_at > now()
  and exists (
    select 1
    from public.published_product_listings as listing
    join public.public_shop_profiles as profile
      on profile.shop_id = listing.shop_id
    where listing.shop_id = deal.shop_id
      and listing.id = deal.listing_id
      and listing.is_published
      and profile.is_enabled
  );

revoke all on table public.public_storefront_shops from public, anon, authenticated;
revoke all on table public.public_storefront_listings from public, anon, authenticated;
revoke all on table public.public_storefront_deals from public, anon, authenticated;
grant select on table public.public_storefront_shops to anon, authenticated;
grant select on table public.public_storefront_listings to anon, authenticated;
grant select on table public.public_storefront_deals to anon, authenticated;

revoke all on function public.ensure_public_shop_profile() from public, anon, authenticated;
revoke all on function public.can_manage_public_storefront(uuid) from public, anon, authenticated;
revoke all on function public.validate_deal() from public, anon, authenticated;
revoke all on function public.validate_listing_price_change() from public, anon, authenticated;

grant execute on function public.can_manage_public_storefront(uuid) to authenticated;
