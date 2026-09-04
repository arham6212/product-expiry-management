drop function if exists public.create_manual_product_for_barcode(uuid, text, text, text, text);
drop function if exists public.create_product_for_barcode(uuid, text, text, text, text, text, text);
drop function if exists private.resolve_catalog_product_for_barcode(
  uuid, text, text, text, text, text, text, text, text, text
);

drop index if exists public.products_shop_catalog_product_key;

alter table public.catalog_products
drop constraint catalog_products_source_check;
alter table public.catalog_products
add constraint catalog_products_source_check
check (source in ('open_food_facts', 'verified_manual'));

drop policy if exists "Members can insert local products" on public.products;
create policy "Members can insert products"
on public.products for insert
to authenticated
with check ((select public.is_shop_member(shop_id)));

grant insert, update on table public.products to authenticated;
grant insert, update on table public.product_barcodes to authenticated;

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
    shop_id, name, brand, image_url, source, source_reference
  )
  values (
    target_shop_id, normalized_name, normalized_brand, product_image_url,
    'open_food_facts', nullif(btrim(product_source_reference), '')
  )
  returning * into created_product;

  insert into public.product_barcodes (
    shop_id, product_id, barcode, format, is_primary
  )
  values (
    target_shop_id, created_product.id, normalized_barcode, barcode_format, true
  );

  return query
  select created_product.id, created_product.shop_id, created_product.name,
    created_product.brand, created_product.image_url, created_product.source,
    created_product.source_reference, created_product.created_at,
    created_product.updated_at, true;
end;
$$;

create function public.create_manual_product_for_barcode(
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
language plpgsql
set search_path = ''
as $$
declare
  saved_product record;
  manual_product public.products;
begin
  select external_product.*
  into saved_product
  from public.create_product_for_barcode(
    target_shop_id, normalized_barcode, barcode_format, product_name,
    product_brand, null, null
  ) as external_product;

  if not saved_product.was_created then
    return query
    select saved_product.id, saved_product.shop_id, saved_product.name,
      saved_product.brand, saved_product.image_url, saved_product.source,
      saved_product.source_reference, saved_product.created_at,
      saved_product.updated_at, false;
    return;
  end if;

  update public.products as product
  set source = 'local_manual', source_reference = null
  where product.shop_id = target_shop_id and product.id = saved_product.id
  returning product.* into manual_product;

  if not found then
    raise exception using errcode = 'P0002', message = 'Saved Product could not be read.';
  end if;

  return query
  select manual_product.id, manual_product.shop_id, manual_product.name,
    manual_product.brand, manual_product.image_url, manual_product.source,
    manual_product.source_reference, manual_product.created_at,
    manual_product.updated_at, true;
end;
$$;

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
