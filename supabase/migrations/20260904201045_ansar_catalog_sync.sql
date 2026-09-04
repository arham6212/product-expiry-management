-- Persist trusted Ansar observations without changing shop-owned inventory.

alter table public.catalog_products
  add column product_family text,
  add column variant_name text,
  add column product_type text,
  add column pack_count integer,
  add column unit_quantity numeric,
  add column unit_quantity_unit text,
  add column total_quantity numeric,
  add column total_quantity_unit text,
  add column packaging_display text,
  add column category text,
  add column subcategory text,
  add column country_of_origin text,
  add column manufacturer text;

alter table public.catalog_products
  add constraint catalog_products_pack_count_check
    check (pack_count is null or pack_count between 1 and 2147483647),
  add constraint catalog_products_unit_quantity_check
    check (unit_quantity is null or unit_quantity > 0),
  add constraint catalog_products_total_quantity_check
    check (total_quantity is null or total_quantity > 0);

create table public.catalog_product_observations (
  id uuid primary key default gen_random_uuid(),
  catalog_product_id uuid not null
    references public.catalog_products(id) on delete cascade,
  source text not null check (source = 'ansar_gallery_qatar'),
  barcode text not null check (
    barcode ~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$'
  ),
  ansar_sku text,
  source_product_url text not null check (
    source_product_url ~ '^https://(www\.)?ansargallery\.com/'
  ),
  data_confidence numeric check (
    data_confidence is null or data_confidence between 0 and 1
  ),
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_product_observations_seen_check
    check (first_seen_at <= last_seen_at),
  constraint catalog_product_observations_source_url_key
    unique (source, source_product_url)
);

create index catalog_product_observations_catalog_product_id_idx
on public.catalog_product_observations (catalog_product_id);

alter table public.catalog_product_observations enable row level security;
revoke all on table public.catalog_product_observations from public, anon, authenticated;
grant select, insert, update on table public.catalog_product_observations to service_role;
grant select, insert, update on table public.catalog_products to service_role;
grant select, insert, update on table public.catalog_product_barcodes to service_role;

create trigger catalog_product_observations_set_updated_at
before update on public.catalog_product_observations
for each row execute function public.set_updated_at();

create function private.is_valid_global_barcode(candidate text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  body_sum integer := 0;
  body_index integer;
  candidate_length integer := char_length(candidate);
begin
  if candidate !~ '^[0-9]+$'
    or candidate_length not in (8, 12, 13, 14)
    or candidate ~ '^([0-9])\1+$'
    or candidate like '499990%'
    or (candidate_length = 13 and candidate ~ '^[0-9]{6}0{7}$')
    or (candidate_length in (13, 14) and substring(candidate from 1 for 2)::integer between 20 and 29)
  then
    return false;
  end if;

  for body_index in 1..(candidate_length - 1) loop
    body_sum := body_sum
      + substring(candidate from candidate_length - body_index for 1)::integer
        * case when body_index % 2 = 1 then 3 else 1 end;
  end loop;

  return (10 - body_sum % 10) % 10
    = right(candidate, 1)::integer;
end;
$$;

revoke all on function private.is_valid_global_barcode(text)
from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.is_valid_global_barcode(text) to service_role;

create function public.ingest_ansar_catalog_observation(observation jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_barcode text := btrim(observation ->> 'global_barcode');
  barcode_format text := btrim(observation ->> 'barcode_format');
  normalized_name text := regexp_replace(btrim(observation ->> 'canonical_name'), '\s+', ' ', 'g');
  normalized_brand text := nullif(regexp_replace(btrim(observation ->> 'brand'), '\s+', ' ', 'g'), '');
  normalized_image text := nullif(btrim(observation ->> 'primary_image_url'), '');
  normalized_source_url text := btrim(observation ->> 'source_product_url');
  observed_first timestamptz := (observation ->> 'first_seen_at')::timestamptz;
  observed_last timestamptz := (observation ->> 'last_seen_at')::timestamptz;
  confidence numeric := nullif(observation ->> 'data_confidence', '')::numeric;
  global_product public.catalog_products;
  existing_observation_product uuid;
  inserted_product boolean := false;
  enriched_product boolean := false;
begin
  if observation ->> 'source' is distinct from 'Ansar Gallery Qatar' then
    raise exception using errcode = '22023', message = 'Only Ansar Gallery Qatar observations are accepted.';
  end if;
  if not coalesce(private.is_valid_global_barcode(normalized_barcode), false) then
    raise exception using errcode = '22023', message = 'A valid global GTIN is required.';
  end if;
  if barcode_format is distinct from (case char_length(normalized_barcode)
    when 8 then 'ean8' when 12 then 'upc_a' when 13 then 'ean13' when 14 then 'gtin14'
  end) then
    raise exception using errcode = '22023', message = 'Barcode format does not match its length.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 1 and 240 then
    raise exception using errcode = '22023', message = 'Canonical name must be 1 to 240 characters.';
  end if;
  if normalized_brand is not null and char_length(normalized_brand) > 240 then
    raise exception using errcode = '22023', message = 'Brand must be 240 characters or fewer.';
  end if;
  if normalized_image is not null and normalized_image !~ '^https?://' then
    raise exception using errcode = '22023', message = 'Image URL must use HTTP or HTTPS.';
  end if;
  if normalized_source_url is null
    or normalized_source_url !~ '^https://(www\.)?ansargallery\.com/' then
    raise exception using errcode = '22023', message = 'Ansar source URL is invalid.';
  end if;
  if confidence is not null and confidence not between 0 and 1 then
    raise exception using errcode = '22023', message = 'Confidence must be between zero and one.';
  end if;
  if observed_first is null or observed_last is null or observed_first > observed_last then
    raise exception using errcode = '22023', message = 'Observation timestamps are invalid.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('catalog-barcode:' || normalized_barcode, 0)
  );

  select catalog.*
  into global_product
  from public.catalog_product_barcodes mapping
  join public.catalog_products catalog on catalog.id = mapping.catalog_product_id
  where mapping.barcode = normalized_barcode
  for update of catalog;

  if global_product.id is null then
    insert into public.catalog_products (
      canonical_name, brand, image_url, source, source_reference,
      product_family, variant_name, product_type, pack_count,
      unit_quantity, unit_quantity_unit, total_quantity, total_quantity_unit,
      packaging_display, category, subcategory, country_of_origin, manufacturer
    ) values (
      normalized_name, normalized_brand, normalized_image, 'user_contributed', null,
      nullif(btrim(observation ->> 'product_family'), ''),
      nullif(btrim(observation ->> 'variant_name'), ''),
      nullif(btrim(observation ->> 'product_type'), ''),
      nullif(observation ->> 'pack_count', '')::integer,
      nullif(observation ->> 'unit_quantity', '')::numeric,
      nullif(btrim(observation ->> 'unit_quantity_unit'), ''),
      nullif(observation ->> 'total_quantity', '')::numeric,
      nullif(btrim(observation ->> 'total_quantity_unit'), ''),
      nullif(btrim(observation ->> 'packaging_display'), ''),
      nullif(btrim(observation ->> 'category'), ''),
      nullif(btrim(observation ->> 'subcategory'), ''),
      nullif(btrim(observation ->> 'country_of_origin'), ''),
      nullif(btrim(observation ->> 'manufacturer'), '')
    )
    returning * into global_product;
    inserted_product := true;

    insert into public.catalog_product_barcodes (catalog_product_id, barcode, format)
    values (global_product.id, normalized_barcode, barcode_format);
  else
    enriched_product :=
      (global_product.brand is null and normalized_brand is not null)
      or (global_product.image_url is null and normalized_image is not null)
      or (global_product.product_family is null and nullif(btrim(observation ->> 'product_family'), '') is not null)
      or (global_product.variant_name is null and nullif(btrim(observation ->> 'variant_name'), '') is not null)
      or (global_product.product_type is null and nullif(btrim(observation ->> 'product_type'), '') is not null)
      or (global_product.pack_count is null and nullif(observation ->> 'pack_count', '') is not null)
      or (global_product.unit_quantity is null and nullif(observation ->> 'unit_quantity', '') is not null)
      or (global_product.unit_quantity_unit is null and nullif(btrim(observation ->> 'unit_quantity_unit'), '') is not null)
      or (global_product.total_quantity is null and nullif(observation ->> 'total_quantity', '') is not null)
      or (global_product.total_quantity_unit is null and nullif(btrim(observation ->> 'total_quantity_unit'), '') is not null)
      or (global_product.packaging_display is null and nullif(btrim(observation ->> 'packaging_display'), '') is not null)
      or (global_product.category is null and nullif(btrim(observation ->> 'category'), '') is not null)
      or (global_product.subcategory is null and nullif(btrim(observation ->> 'subcategory'), '') is not null)
      or (global_product.country_of_origin is null and nullif(btrim(observation ->> 'country_of_origin'), '') is not null)
      or (global_product.manufacturer is null and nullif(btrim(observation ->> 'manufacturer'), '') is not null);

    if enriched_product then
      update public.catalog_products catalog
      set brand = coalesce(catalog.brand, normalized_brand),
          image_url = coalesce(catalog.image_url, normalized_image),
          product_family = coalesce(catalog.product_family, nullif(btrim(observation ->> 'product_family'), '')),
          variant_name = coalesce(catalog.variant_name, nullif(btrim(observation ->> 'variant_name'), '')),
          product_type = coalesce(catalog.product_type, nullif(btrim(observation ->> 'product_type'), '')),
          pack_count = coalesce(catalog.pack_count, nullif(observation ->> 'pack_count', '')::integer),
          unit_quantity = coalesce(catalog.unit_quantity, nullif(observation ->> 'unit_quantity', '')::numeric),
          unit_quantity_unit = coalesce(catalog.unit_quantity_unit, nullif(btrim(observation ->> 'unit_quantity_unit'), '')),
          total_quantity = coalesce(catalog.total_quantity, nullif(observation ->> 'total_quantity', '')::numeric),
          total_quantity_unit = coalesce(catalog.total_quantity_unit, nullif(btrim(observation ->> 'total_quantity_unit'), '')),
          packaging_display = coalesce(catalog.packaging_display, nullif(btrim(observation ->> 'packaging_display'), '')),
          category = coalesce(catalog.category, nullif(btrim(observation ->> 'category'), '')),
          subcategory = coalesce(catalog.subcategory, nullif(btrim(observation ->> 'subcategory'), '')),
          country_of_origin = coalesce(catalog.country_of_origin, nullif(btrim(observation ->> 'country_of_origin'), '')),
          manufacturer = coalesce(catalog.manufacturer, nullif(btrim(observation ->> 'manufacturer'), ''))
      where catalog.id = global_product.id
      returning catalog.* into global_product;
    end if;
  end if;

  select existing.catalog_product_id
  into existing_observation_product
  from public.catalog_product_observations existing
  where existing.source = 'ansar_gallery_qatar'
    and existing.source_product_url = normalized_source_url;

  if existing_observation_product is not null
    and existing_observation_product <> global_product.id then
    raise exception using errcode = '23505', message = 'Ansar source URL is linked to another CatalogProduct.';
  end if;

  insert into public.catalog_product_observations (
    catalog_product_id, source, barcode, ansar_sku, source_product_url,
    data_confidence, first_seen_at, last_seen_at, details
  ) values (
    global_product.id, 'ansar_gallery_qatar', normalized_barcode,
    nullif(btrim(observation ->> 'ansar_sku'), ''), normalized_source_url,
    confidence, observed_first, observed_last,
    jsonb_strip_nulls(jsonb_build_object(
      'source_display_name', nullif(btrim(observation ->> 'source_display_name'), ''),
      'product_family', nullif(btrim(observation ->> 'product_family'), ''),
      'variant_name', nullif(btrim(observation ->> 'variant_name'), ''),
      'product_type', nullif(btrim(observation ->> 'product_type'), ''),
      'pack_count', nullif(observation ->> 'pack_count', '')::integer,
      'unit_quantity', nullif(observation ->> 'unit_quantity', '')::numeric,
      'unit_quantity_unit', nullif(btrim(observation ->> 'unit_quantity_unit'), ''),
      'total_quantity', nullif(observation ->> 'total_quantity', '')::numeric,
      'total_quantity_unit', nullif(btrim(observation ->> 'total_quantity_unit'), ''),
      'packaging_display', nullif(btrim(observation ->> 'packaging_display'), ''),
      'category', nullif(btrim(observation ->> 'category'), ''),
      'subcategory', nullif(btrim(observation ->> 'subcategory'), ''),
      'country_of_origin', nullif(btrim(observation ->> 'country_of_origin'), ''),
      'manufacturer', nullif(btrim(observation ->> 'manufacturer'), ''),
      'primary_image_url', normalized_image
    ))
  )
  on conflict (source, source_product_url) do update
  set ansar_sku = coalesce(excluded.ansar_sku, public.catalog_product_observations.ansar_sku),
      barcode = excluded.barcode,
      data_confidence = coalesce(excluded.data_confidence, public.catalog_product_observations.data_confidence),
      first_seen_at = least(public.catalog_product_observations.first_seen_at, excluded.first_seen_at),
      last_seen_at = greatest(public.catalog_product_observations.last_seen_at, excluded.last_seen_at),
      details = public.catalog_product_observations.details || excluded.details;

  return jsonb_build_object(
    'catalog_product_id', global_product.id,
    'barcode', normalized_barcode,
    'status', case
      when inserted_product then 'inserted'
      when enriched_product then 'enriched'
      else 'unchanged'
    end
  );
end;
$$;

revoke all on function public.ingest_ansar_catalog_observation(jsonb)
from public, anon, authenticated;
grant execute on function public.ingest_ansar_catalog_observation(jsonb)
to service_role;

create function public.find_catalog_product_by_barcode(normalized_barcode text)
returns table (
  id uuid,
  canonical_name text,
  brand text,
  image_url text,
  product_family text,
  variant_name text,
  product_type text,
  pack_count integer,
  unit_quantity numeric,
  unit_quantity_unit text,
  total_quantity numeric,
  total_quantity_unit text,
  packaging_display text,
  category text,
  subcategory text,
  country_of_origin text,
  manufacturer text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if not coalesce(private.is_valid_global_barcode(btrim(normalized_barcode)), false) then
    raise exception using errcode = '22023', message = 'A valid global GTIN is required.';
  end if;

  return query
  select catalog.id, catalog.canonical_name, catalog.brand, catalog.image_url,
    catalog.product_family, catalog.variant_name, catalog.product_type,
    catalog.pack_count, catalog.unit_quantity, catalog.unit_quantity_unit,
    catalog.total_quantity, catalog.total_quantity_unit, catalog.packaging_display,
    catalog.category, catalog.subcategory, catalog.country_of_origin, catalog.manufacturer
  from public.catalog_product_barcodes mapping
  join public.catalog_products catalog on catalog.id = mapping.catalog_product_id
  where mapping.barcode = btrim(normalized_barcode);
end;
$$;

revoke all on function public.find_catalog_product_by_barcode(text)
from public, anon, authenticated;
grant execute on function public.find_catalog_product_by_barcode(text)
to authenticated, service_role;

create function public.create_product_from_catalog(
  target_shop_id uuid,
  normalized_barcode text,
  barcode_format text,
  product_name text,
  product_brand text default null,
  product_image_url text default null
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
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.catalog_product_barcodes mapping
    where mapping.barcode = btrim(normalized_barcode)
  ) then
    raise exception using errcode = 'P0002', message = 'CatalogProduct was not found.';
  end if;

  return query
  select * from private.resolve_catalog_product_for_barcode(
    target_shop_id,
    btrim(normalized_barcode),
    barcode_format,
    product_name,
    product_brand,
    product_image_url,
    'local_manual',
    null,
    'user_contributed',
    null
  );
end;
$$;

revoke all on function public.create_product_from_catalog(uuid,text,text,text,text,text)
from public, anon, authenticated;
grant execute on function public.create_product_from_catalog(uuid,text,text,text,text,text)
to authenticated;

create function public.verify_ansar_catalog_sync(target_barcodes text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with requested as (
    select distinct barcode
    from unnest(target_barcodes) as barcode
  ), matched as (
    select requested.barcode, mapping.catalog_product_id
    from requested
    join public.catalog_product_barcodes mapping using (barcode)
  )
  select jsonb_build_object(
    'requested', (select count(*) from requested),
    'matched', (select count(*) from matched),
    'distinct_catalog_products', (select count(distinct catalog_product_id) from matched),
    'missing', coalesce((
      select jsonb_agg(requested.barcode order by requested.barcode)
      from requested left join matched using (barcode)
      where matched.barcode is null
    ), '[]'::jsonb),
    'catalog_products', (select count(*) from public.catalog_products),
    'catalog_product_barcodes', (select count(*) from public.catalog_product_barcodes),
    'catalog_product_observations', (select count(*) from public.catalog_product_observations),
    'protected_counts', jsonb_build_object(
      'products', (select count(*) from public.products),
      'product_barcodes', (select count(*) from public.product_barcodes),
      'batches', (select count(*) from public.batches),
      'inventory_movements', (select count(*) from public.inventory_movements),
      'published_product_listings', (select count(*) from public.published_product_listings),
      'deals', (select count(*) from public.deals)
    )
  );
$$;

revoke all on function public.verify_ansar_catalog_sync(text[])
from public, anon, authenticated;
grant execute on function public.verify_ansar_catalog_sync(text[])
to service_role;
