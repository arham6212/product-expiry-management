begin;
select plan(27);

create temporary table protected_counts_before as
select
  (select count(*) from public.products) as products,
  (select count(*) from public.product_barcodes) as product_barcodes,
  (select count(*) from public.batches) as batches,
  (select count(*) from public.inventory_movements) as inventory_movements,
  (select count(*) from public.published_product_listings) as listings,
  (select count(*) from public.deals) as deals;

select has_table('public', 'catalog_product_observations', 'Ansar provenance table exists');
select has_column('public', 'catalog_products', 'packaging_display', 'catalog packaging is available');
select has_function(
  'public', 'ingest_ansar_catalog_observation', array['jsonb'],
  'service-only Ansar ingestion RPC exists'
);
select has_function(
  'public', 'find_catalog_product_by_barcode', array['text'],
  'authenticated global lookup RPC exists'
);

set local role anon;
select throws_ok(
  $$select public.ingest_ansar_catalog_observation('{}'::jsonb)$$,
  '42501', null, 'anonymous cannot execute ingestion'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.ingest_ansar_catalog_observation('{}'::jsonb)$$,
  '42501', null, 'authenticated clients cannot execute ingestion'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

select results_eq(
  $$select public.ingest_ansar_catalog_observation(
    '{
      "source":"Ansar Gallery Qatar",
      "global_barcode":"5000112519945",
      "barcode_format":"ean13",
      "canonical_name":"Ansar Cola 330ml",
      "brand":"Ansar Brand",
      "primary_image_url":"https://media.ansargallery.com/cola.jpg",
      "ansar_sku":"ANSAR-001",
      "source_product_url":"https://www.ansargallery.com/en/ansar-cola-5000112519945",
      "data_confidence":0.95,
      "first_seen_at":"2026-09-01T00:00:00Z",
      "last_seen_at":"2026-09-01T00:00:00Z",
      "product_family":"Cola",
      "variant_name":"Original",
      "product_type":"packaged",
      "pack_count":1,
      "unit_quantity":330,
      "unit_quantity_unit":"ml",
      "total_quantity":330,
      "total_quantity_unit":"ml",
      "packaging_display":"330ml",
      "category":"Beverages",
      "subcategory":"Soft Drinks"
    }'::jsonb
  ) ->> 'status'$$,
  $$values ('inserted'::text)$$,
  'first import inserts one CatalogProduct'
);

select is(
  (select count(*) from public.catalog_product_barcodes where barcode = '5000112519945'),
  1::bigint,
  'first import creates one global barcode mapping'
);
select is(
  (select count(*) from public.catalog_product_observations where barcode = '5000112519945'),
  1::bigint,
  'first import records one provenance observation'
);

select results_eq(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Ansar Gallery Qatar","global_barcode":"5000112519945","barcode_format":"ean13","canonical_name":"Replacement name","brand":"Replacement brand","source_product_url":"https://www.ansargallery.com/en/ansar-cola-5000112519945","data_confidence":0.95,"first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-02T00:00:00Z"}'::jsonb
  ) ->> 'status'$$,
  $$values ('unchanged'::text)$$,
  'repeated import is idempotent'
);
select results_eq(
  $$select canonical_name, brand from public.catalog_products catalog
    join public.catalog_product_barcodes mapping on mapping.catalog_product_id = catalog.id
    where mapping.barcode = '5000112519945'$$,
  $$values ('Ansar Cola 330ml'::text, 'Ansar Brand'::text)$$,
  'non-empty catalog values are never overwritten'
);

insert into public.catalog_products (id, canonical_name, source)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Verified product', 'verified_manual');
insert into public.catalog_product_barcodes (catalog_product_id, barcode, format)
values ('aaaaaaaa-0000-0000-0000-000000000001', '8690101368943', 'ean13');

select results_eq(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Ansar Gallery Qatar","global_barcode":"8690101368943","barcode_format":"ean13","canonical_name":"Crawler name","brand":"Filled Brand","source_product_url":"https://www.ansargallery.com/en/verified-8690101368943","data_confidence":0.9,"first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-01T00:00:00Z"}'::jsonb
  ) ->> 'status'$$,
  $$values ('enriched'::text)$$,
  'empty fields on an existing product are enriched'
);
select results_eq(
  $$select id, canonical_name, brand from public.catalog_products
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  $$values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'Verified product'::text, 'Filled Brand'::text)$$,
  'existing barcode identity and verified name are preserved'
);

select throws_ok(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Ansar Gallery Qatar","global_barcode":"2901234567893","barcode_format":"ean13","canonical_name":"Weighted","source_product_url":"https://www.ansargallery.com/en/weighted","first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-01T00:00:00Z"}'::jsonb
  )$$,
  '22023', 'A valid global GTIN is required.',
  'restricted-distribution identifiers are rejected'
);
select throws_ok(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Snoonu","global_barcode":"5012345678900","barcode_format":"ean13","canonical_name":"Wrong source","source_product_url":"https://www.ansargallery.com/en/wrong-source","first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-01T00:00:00Z"}'::jsonb
  )$$,
  '22023', 'Only Ansar Gallery Qatar observations are accepted.',
  'non-Ansar source cannot create global identity'
);

select lives_ok(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Ansar Gallery Qatar","global_barcode":"017273501615","barcode_format":"upc_a","canonical_name":"Leading zero UPC","source_product_url":"https://www.ansargallery.com/en/upc-017273501615","first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-01T00:00:00Z"}'::jsonb
  )$$,
  'leading-zero UPC is accepted as text'
);
select ok(
  exists (select 1 from public.catalog_product_barcodes where barcode = '017273501615'),
  'leading zero remains present in the stored barcode'
);

select lives_ok(
  $$select public.ingest_ansar_catalog_observation(
    '{"source":"Ansar Gallery Qatar","global_barcode":"05000112519945","barcode_format":"gtin14","canonical_name":"Distinct multipack","source_product_url":"https://www.ansargallery.com/en/multipack-05000112519945","first_seen_at":"2026-09-01T00:00:00Z","last_seen_at":"2026-09-01T00:00:00Z"}'::jsonb
  )$$,
  'a distinct GTIN variant imports successfully'
);
select is(
  (select count(distinct catalog_product_id) from public.catalog_product_barcodes
   where barcode in ('5000112519945', '017273501615', '05000112519945')),
  3::bigint,
  'different GTIN variants remain separate products'
);

select results_eq(
  $$select source, ansar_sku, source_product_url
    from public.catalog_product_observations where barcode = '5000112519945'$$,
  $$values ('ansar_gallery_qatar'::text, 'ANSAR-001'::text,
    'https://www.ansargallery.com/en/ansar-cola-5000112519945'::text)$$,
  'Ansar SKU and URL remain provenance rather than identity'
);

select results_eq(
  $$select (public.verify_ansar_catalog_sync(array['5000112519945','017273501615']) ->> 'matched')::integer$$,
  $$values (2)$$,
  'verification RPC resolves imported barcodes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select results_eq(
  $$select canonical_name, packaging_display
    from public.find_catalog_product_by_barcode('5000112519945')$$,
  $$values ('Ansar Cola 330ml'::text, '330ml'::text)$$,
  'authenticated scan lookup returns safe imported catalog fields'
);
select throws_ok(
  $$select * from public.catalog_products$$,
  '42501', null,
  'authenticated users still cannot read the global catalog table directly'
);

reset role;
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ingest_ansar_catalog_observation'
     and has_function_privilege('anon', p.oid, 'execute')),
  0::bigint,
  'anon has no ingestion execute grant'
);
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ingest_ansar_catalog_observation'
     and has_function_privilege('authenticated', p.oid, 'execute')),
  0::bigint,
  'authenticated has no ingestion execute grant'
);
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ingest_ansar_catalog_observation'
     and has_function_privilege('service_role', p.oid, 'execute')),
  1::bigint,
  'service_role alone can execute ingestion'
);

select results_eq(
  $$select products, product_barcodes, batches, inventory_movements, listings, deals
    from protected_counts_before$$,
  $$select
      (select count(*) from public.products),
      (select count(*) from public.product_barcodes),
      (select count(*) from public.batches),
      (select count(*) from public.inventory_movements),
      (select count(*) from public.published_product_listings),
      (select count(*) from public.deals)$$,
  'ingestion leaves shop products, prices, batches, inventory, listings, and deals untouched'
);

select * from finish();
rollback;
