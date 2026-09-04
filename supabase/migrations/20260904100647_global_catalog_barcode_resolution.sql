-- Resolve scanned barcodes through one protected global identity while keeping
-- inventory ownership and all existing public RPC contracts shop-scoped.

alter table public.catalog_products
drop constraint catalog_products_source_check;

alter table public.catalog_products
add constraint catalog_products_source_check
check (source in ('open_food_facts', 'verified_manual', 'user_contributed'));

create unique index products_shop_catalog_product_key
on public.products (shop_id, catalog_product_id)
where catalog_product_id is not null;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.resolve_catalog_product_for_barcode(
  target_shop_id uuid,
  normalized_barcode text,
  barcode_format text,
  product_name text,
  product_brand text,
  product_image_url text,
  shop_product_source text,
  shop_source_reference text,
  catalog_source text,
  catalog_source_reference text
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
  normalized_shop_reference text := nullif(btrim(shop_source_reference), '');
  normalized_catalog_reference text := nullif(btrim(catalog_source_reference), '');
  global_product public.catalog_products;
  existing_product public.products;
  saved_product public.products;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
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
  if normalized_brand is not null and char_length(normalized_brand) > 240 then
    raise exception using errcode = '22023', message = 'Product brand must be 240 characters or less.';
  end if;
  if product_image_url is not null and product_image_url !~ '^https?://' then
    raise exception using errcode = '22023', message = 'Product image URL must use HTTP or HTTPS.';
  end if;
  if shop_product_source not in ('local_manual', 'open_food_facts') then
    raise exception using errcode = '22023', message = 'Shop Product provenance is invalid.';
  end if;
  if catalog_source not in ('open_food_facts', 'user_contributed') then
    raise exception using errcode = '22023', message = 'CatalogProduct provenance is invalid.';
  end if;

  -- Every resolver takes the global lock first and the shop lock second. This
  -- makes both cross-shop catalog creation and same-shop Product creation
  -- deterministic without relying on conflict recovery after partial writes.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-barcode:' || normalized_barcode, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'shop-barcode:' || target_shop_id::text || ':' || normalized_barcode,
      0
    )
  );

  select catalog.*
  into global_product
  from public.catalog_product_barcodes mapping
  join public.catalog_products catalog on catalog.id = mapping.catalog_product_id
  where mapping.barcode = normalized_barcode;

  if not found and normalized_catalog_reference is not null then
    select catalog.*
    into global_product
    from public.catalog_products catalog
    where catalog.source = catalog_source
      and catalog.source_reference = normalized_catalog_reference;
  end if;

  if global_product.id is null then
    insert into public.catalog_products (
      canonical_name,
      brand,
      image_url,
      source,
      source_reference
    )
    values (
      normalized_name,
      normalized_brand,
      product_image_url,
      catalog_source,
      normalized_catalog_reference
    )
    returning * into global_product;
  end if;

  insert into public.catalog_product_barcodes (
    catalog_product_id,
    barcode,
    format
  )
  values (
    global_product.id,
    normalized_barcode,
    barcode_format
  )
  on conflict (barcode) do nothing;

  if exists (
    select 1
    from public.catalog_product_barcodes mapping
    where mapping.barcode = normalized_barcode
      and mapping.catalog_product_id <> global_product.id
  ) then
    raise exception using
      errcode = '23505',
      message = 'Barcode is already linked to a conflicting CatalogProduct.';
  end if;

  select product.*
  into existing_product
  from public.product_barcodes mapping
  join public.products product
    on product.shop_id = mapping.shop_id
   and product.id = mapping.product_id
  where mapping.shop_id = target_shop_id
    and mapping.barcode = normalized_barcode;

  if found then
    if existing_product.catalog_product_id is null then
      update public.products product
      set catalog_product_id = global_product.id
      where product.shop_id = target_shop_id
        and product.id = existing_product.id
      returning product.* into existing_product;
    elsif existing_product.catalog_product_id <> global_product.id then
      raise exception using
        errcode = '23505',
        message = 'Barcode is already linked to a conflicting CatalogProduct.';
    end if;

    return query
    select existing_product.id, existing_product.shop_id, existing_product.name,
      existing_product.brand, existing_product.image_url, existing_product.source,
      existing_product.source_reference, existing_product.created_at,
      existing_product.updated_at, false;
    return;
  end if;

  select product.*
  into existing_product
  from public.products product
  where product.shop_id = target_shop_id
    and product.catalog_product_id = global_product.id;

  if found then
    insert into public.product_barcodes (
      shop_id,
      product_id,
      barcode,
      format,
      is_primary
    )
    values (
      target_shop_id,
      existing_product.id,
      normalized_barcode,
      barcode_format,
      not exists (
        select 1 from public.product_barcodes mapping
        where mapping.product_id = existing_product.id
      )
    );

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
    source_reference,
    catalog_product_id
  )
  values (
    target_shop_id,
    normalized_name,
    normalized_brand,
    product_image_url,
    shop_product_source,
    normalized_shop_reference,
    global_product.id
  )
  returning * into saved_product;

  insert into public.product_barcodes (
    shop_id,
    product_id,
    barcode,
    format,
    is_primary
  )
  values (
    target_shop_id,
    saved_product.id,
    normalized_barcode,
    barcode_format,
    true
  );

  return query
  select saved_product.id, saved_product.shop_id, saved_product.name,
    saved_product.brand, saved_product.image_url, saved_product.source,
    saved_product.source_reference, saved_product.created_at,
    saved_product.updated_at, true;
end;
$$;

create or replace function public.create_product_for_barcode(
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
language sql
security definer
set search_path = ''
as $$
  select *
  from private.resolve_catalog_product_for_barcode(
    target_shop_id,
    normalized_barcode,
    barcode_format,
    product_name,
    product_brand,
    product_image_url,
    'open_food_facts',
    product_source_reference,
    'open_food_facts',
    product_source_reference
  );
$$;

create or replace function public.create_manual_product_for_barcode(
  target_shop_id uuid,
  normalized_barcode text,
  barcode_format text,
  product_name text,
  product_brand text default null
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
language sql
security definer
set search_path = ''
as $$
  select *
  from private.resolve_catalog_product_for_barcode(
    target_shop_id,
    normalized_barcode,
    barcode_format,
    product_name,
    product_brand,
    null,
    'local_manual',
    null,
    'user_contributed',
    null
  );
$$;

-- Barcode and CatalogProduct identity can now change only through the protected
-- resolver. Barcode-less local Product creation remains available with the
-- same client contract and editable shop metadata remains member-scoped.
drop policy "Members can insert products" on public.products;
create policy "Members can insert local products"
on public.products for insert
to authenticated
with check (
  (select public.is_shop_member(shop_id))
  and source = 'local_manual'
  and source_reference is null
  and catalog_product_id is null
);

revoke insert, update on table public.products from authenticated;
grant insert (shop_id, name, brand, image_url, source)
on table public.products to authenticated;
grant update (name, brand, image_url)
on table public.products to authenticated;

revoke insert, update on table public.product_barcodes from authenticated;

revoke all on function private.resolve_catalog_product_for_barcode(
  uuid, text, text, text, text, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.create_product_for_barcode(
  uuid, text, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.create_manual_product_for_barcode(
  uuid, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.create_product_for_barcode(
  uuid, text, text, text, text, text, text
) to authenticated;
grant execute on function public.create_manual_product_for_barcode(
  uuid, text, text, text, text
) to authenticated;
