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
    target_shop_id,
    normalized_barcode,
    barcode_format,
    product_name,
    product_brand,
    null,
    null
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
  set source = 'local_manual',
      source_reference = null
  where product.shop_id = target_shop_id
    and product.id = saved_product.id
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

revoke all on function public.create_manual_product_for_barcode(uuid, text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.create_manual_product_for_barcode(uuid, text, text, text, text)
  to authenticated;
