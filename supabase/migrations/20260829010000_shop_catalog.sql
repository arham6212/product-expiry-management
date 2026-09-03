create table public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  time_zone text not null default 'UTC' check (char_length(btrim(time_zone)) > 0),
  currency_code text not null default 'USD' check (currency_code ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.shop_memberships (
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'staff')),
  created_at timestamptz not null default now(),
  primary key (shop_id, user_id)
);

create index shop_memberships_user_id_idx on public.shop_memberships(user_id);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 240),
  brand text check (brand is null or char_length(btrim(brand)) between 1 and 240),
  image_url text check (image_url is null or image_url ~ '^https?://'),
  source text not null check (source in ('local_manual', 'open_food_facts')),
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_shop_id_id_key unique (shop_id, id)
);

create index products_shop_id_idx on public.products(shop_id);

create table public.product_barcodes (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  product_id uuid not null,
  barcode text not null check (barcode ~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$'),
  format text not null check (format in ('ean8', 'upc_a', 'ean13', 'gtin14', 'unknown')),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint product_barcodes_product_shop_fkey
    foreign key (shop_id, product_id)
    references public.products(shop_id, id)
    on delete cascade,
  constraint product_barcodes_shop_barcode_key unique (shop_id, barcode)
);

create index product_barcodes_product_id_idx on public.product_barcodes(product_id);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger shops_set_updated_at
before update on public.shops
for each row execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

alter table public.shops enable row level security;
alter table public.shop_memberships enable row level security;
alter table public.products enable row level security;
alter table public.product_barcodes enable row level security;

revoke all on table public.shops from anon, authenticated;
revoke all on table public.shop_memberships from anon, authenticated;
revoke all on table public.products from anon, authenticated;
revoke all on table public.product_barcodes from anon, authenticated;

grant select, update on table public.shops to authenticated;
grant select on table public.shop_memberships to authenticated;
grant select, insert, update on table public.products to authenticated;
grant select, insert, update on table public.product_barcodes to authenticated;

create function public.is_shop_member(target_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.shop_memberships membership
      where membership.shop_id = target_shop_id
        and membership.user_id = (select auth.uid())
    );
$$;

create policy "Members can read their shops"
on public.shops for select
to authenticated
using ((select public.is_shop_member(id)));

create policy "Members can update their shops"
on public.shops for update
to authenticated
using ((select public.is_shop_member(id)))
with check ((select public.is_shop_member(id)));

create policy "Users can read their memberships"
on public.shop_memberships for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Members can read products"
on public.products for select
to authenticated
using ((select public.is_shop_member(shop_id)));

create policy "Members can insert products"
on public.products for insert
to authenticated
with check ((select public.is_shop_member(shop_id)));

create policy "Members can update products"
on public.products for update
to authenticated
using ((select public.is_shop_member(shop_id)))
with check ((select public.is_shop_member(shop_id)));

create policy "Members can read product barcodes"
on public.product_barcodes for select
to authenticated
using ((select public.is_shop_member(shop_id)));

create policy "Members can insert product barcodes"
on public.product_barcodes for insert
to authenticated
with check ((select public.is_shop_member(shop_id)));

create policy "Members can update product barcodes"
on public.product_barcodes for update
to authenticated
using ((select public.is_shop_member(shop_id)))
with check ((select public.is_shop_member(shop_id)));

create function public.create_shop_with_owner(shop_name text)
returns public.shops
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_name text := regexp_replace(btrim(shop_name), '\s+', ' ', 'g');
  created_shop public.shops;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'Shop name must be 1 to 120 characters.';
  end if;

  insert into public.shops (name)
  values (normalized_name)
  returning * into created_shop;

  insert into public.shop_memberships (shop_id, user_id, role)
  values (created_shop.id, caller_id, 'owner');

  return created_shop;
end;
$$;

create function public.create_product_for_barcode(
  target_shop_id uuid,
  normalized_barcode text,
  barcode_format text,
  product_name text,
  product_brand text default null,
  product_image_url text default null,
  product_source_reference text default null
)
returns table (
  id uuid,
  shop_id uuid,
  name text,
  brand text,
  image_url text,
  source text,
  source_reference text,
  created_at timestamptz,
  updated_at timestamptz,
  was_created boolean
)
language plpgsql
set search_path = ''
as $$
declare
  normalized_name text := regexp_replace(btrim(product_name), '\s+', ' ', 'g');
  normalized_brand text := nullif(regexp_replace(btrim(product_brand), '\s+', ' ', 'g'), '');
  existing_product public.products;
  created_product public.products;
begin
  if not public.is_shop_member(target_shop_id) then
    raise exception using errcode = '42501', message = 'Shop membership is required.';
  end if;
  if normalized_barcode !~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$' then
    raise exception using errcode = '22023', message = 'Barcode format is not supported.';
  end if;
  if barcode_format not in ('ean8', 'upc_a', 'ean13', 'gtin14', 'unknown') then
    raise exception using errcode = '22023', message = 'Barcode symbology is not supported.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 1 and 240 then
    raise exception using errcode = '22023', message = 'Product name must be 1 to 240 characters.';
  end if;
  if product_image_url is not null and product_image_url !~ '^https?://' then
    raise exception using errcode = '22023', message = 'Product image URL must use HTTP or HTTPS.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_shop_id::text || ':' || normalized_barcode, 0)
  );

  select product.*
  into existing_product
  from public.product_barcodes mapping
  join public.products product
    on product.shop_id = mapping.shop_id
   and product.id = mapping.product_id
  where mapping.shop_id = target_shop_id
    and mapping.barcode = normalized_barcode;

  if found then
    return query
    select existing_product.id, existing_product.shop_id, existing_product.name,
      existing_product.brand, existing_product.image_url, existing_product.source,
      existing_product.source_reference, existing_product.created_at,
      existing_product.updated_at, false;
    return;
  end if;

  insert into public.products (
    shop_id,
    name,
    brand,
    image_url,
    source,
    source_reference
  )
  values (
    target_shop_id,
    normalized_name,
    normalized_brand,
    product_image_url,
    'open_food_facts',
    nullif(btrim(product_source_reference), '')
  )
  returning * into created_product;

  insert into public.product_barcodes (
    shop_id,
    product_id,
    barcode,
    format,
    is_primary
  )
  values (
    target_shop_id,
    created_product.id,
    normalized_barcode,
    barcode_format,
    true
  );

  return query
  select created_product.id, created_product.shop_id, created_product.name,
    created_product.brand, created_product.image_url, created_product.source,
    created_product.source_reference, created_product.created_at,
    created_product.updated_at, true;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.is_shop_member(uuid) from public, anon, authenticated;
revoke all on function public.create_shop_with_owner(text) from public, anon, authenticated;
revoke all on function public.create_product_for_barcode(uuid, text, text, text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.is_shop_member(uuid) to authenticated;
grant execute on function public.create_shop_with_owner(text) to authenticated;
grant execute on function public.create_product_for_barcode(uuid, text, text, text, text, text, text)
  to authenticated;
