begin;

drop function if exists public.verify_ansar_catalog_sync(text[]);
drop function if exists public.create_product_from_catalog(uuid,text,text,text,text,text);
drop function if exists public.find_catalog_product_by_barcode(text);
drop function if exists public.ingest_ansar_catalog_observation(jsonb);
drop function if exists private.is_valid_global_barcode(text);

drop table if exists public.catalog_product_observations;

alter table public.catalog_products
  drop column if exists product_family,
  drop column if exists variant_name,
  drop column if exists product_type,
  drop column if exists pack_count,
  drop column if exists unit_quantity,
  drop column if exists unit_quantity_unit,
  drop column if exists total_quantity,
  drop column if exists total_quantity_unit,
  drop column if exists packaging_display,
  drop column if exists category,
  drop column if exists subcategory,
  drop column if exists country_of_origin,
  drop column if exists manufacturer;

commit;
