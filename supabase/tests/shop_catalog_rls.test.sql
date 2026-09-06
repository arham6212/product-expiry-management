begin;
select plan(49);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'member@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'other@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'new@example.test');

insert into public.shops (id, name)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Member shop'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Other shop');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'owner');

insert into public.catalog_products (id, canonical_name, source)
values
  ('cccccccc-0000-0000-0000-000000000001', 'Conflict global A', 'verified_manual'),
  ('cccccccc-0000-0000-0000-000000000002', 'Conflict global B', 'verified_manual');

insert into public.catalog_product_barcodes (catalog_product_id, barcode, format)
values ('cccccccc-0000-0000-0000-000000000001', '5901234123457', 'ean13');

insert into public.products (id, shop_id, name, source, catalog_product_id)
values
  ('aaaaaaaa-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Member product', 'local_manual', null),
  ('aaaaaaaa-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Conflicting product', 'local_manual', 'cccccccc-0000-0000-0000-000000000002'),
  ('bbbbbbbb-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Other product', 'local_manual', null);

insert into public.product_barcodes (id, shop_id, product_id, barcode, format, is_primary)
values
  (
    'aaaaaaaa-3333-3333-3333-333333333333',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'aaaaaaaa-1111-1111-1111-111111111111',
    '1234567890123',
    'ean13',
    true
  ),
  (
    'aaaaaaaa-5555-5555-5555-555555555555',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'aaaaaaaa-2222-2222-2222-222222222222',
    '5901234123457',
    'ean13',
    true
  );

insert into public.batches (
  id, shop_id, product_id, expiry_date, current_quantity, created_by
)
values (
  'aaaaaaaa-6666-6666-6666-666666666666',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-1111-1111-1111-111111111111',
  '2026-12-31',
  4,
  '11111111-1111-1111-1111-111111111111'
);

insert into public.inventory_movements (
  id, shop_id, batch_id, movement_type, quantity_delta, created_by, idempotency_key
)
values (
  'aaaaaaaa-7777-7777-7777-777777777777',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaaaaaa-6666-6666-6666-666666666666',
  'received',
  4,
  '11111111-1111-1111-1111-111111111111',
  'catalog-existing-inventory'
);

select has_table('public', 'shops', 'shops table exists');
select has_table('public', 'shop_memberships', 'shop_memberships table exists');
select has_table('public', 'products', 'products table exists');
select has_table('public', 'product_barcodes', 'product_barcodes table exists');

set local role anon;
select throws_ok(
  $$select * from public.products$$,
  '42501',
  null,
  'anonymous users cannot read products'
);
select throws_ok(
  $$insert into public.products (shop_id, name, source)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Blocked anonymous product', 'local_manual')$$,
  '42501',
  null,
  'anonymous users cannot create products'
);
select throws_ok(
  $$select public.create_shop_with_owner('Anonymous shop')$$,
  '42501',
  null,
  'anonymous users cannot create shops'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$select name from public.shops order by name$$,
  $$values ('Member shop'::text)$$,
  'members read only their shops'
);
select results_eq(
  $$select user_id from public.shop_memberships$$,
  $$values ('11111111-1111-1111-1111-111111111111'::uuid)$$,
  'users read only their memberships'
);
select results_eq(
  $$select name from public.products order by name$$,
  $$values ('Conflicting product'::text), ('Member product'::text)$$,
  'members read only their shop products'
);
select results_eq(
  $$select barcode from public.product_barcodes order by barcode$$,
  $$values ('1234567890123'::text), ('5901234123457'::text)$$,
  'members read only their shop barcodes'
);
select lives_ok(
  $$insert into public.products (shop_id, name, source)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'Allowed product',
      'local_manual'
    )$$,
  'members can create products in their shop'
);
select is(
  (
    select count(*)
    from public.product_barcodes
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and barcode not in ('1234567890123', '5901234123457')
  ),
  0::bigint,
  'direct manual Product insert creates no barcode mapping'
);
select throws_ok(
  $$insert into public.products (shop_id, name, source)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Blocked product', 'local_manual')$$,
  '42501',
  null,
  'members cannot create products in another shop'
);
select throws_ok(
  $$insert into public.product_barcodes (shop_id, product_id, barcode, format)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'bbbbbbbb-2222-2222-2222-222222222222',
      '5000112519945',
      'ean13'
    )$$,
  '42501',
  null,
  'members cannot directly create barcode identity mappings'
);
select results_eq(
  $$select was_created from public.create_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '5000112519945',
      'ean13',
      'External product',
      'Brand',
      null,
      '5000112519945'
    )$$,
  $$values (true)$$,
  'first external save creates a product'
);
select results_eq(
  $$select was_created from public.create_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '5000112519945',
      'ean13',
      'Duplicate product',
      null,
      null,
      'duplicate'
    )$$,
  $$values (false)$$,
  'duplicate external save returns the existing product'
);
select is(
  (select count(*) from public.product_barcodes where barcode = '5000112519945'),
  1::bigint,
  'one barcode mapping remains after duplicate save'
);
select results_eq(
  $$select was_created from public.create_manual_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '5012345678900',
      'ean13',
      ' Manual  product ',
      ' Local  brand '
    )$$,
  $$values (true)$$,
  'manual save creates a product through the shared barcode lock'
);
select results_eq(
  $$select name, brand, source, source_reference
    from public.products
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and id = (
        select product_id
        from public.product_barcodes
        where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
          and barcode = '5012345678900'
      )$$,
  $$values ('Manual product'::text, 'Local brand'::text, 'local_manual'::text, null::text)$$,
  'manual save normalizes and persists a usable local Product'
);
select results_eq(
  $$select was_created, source from public.create_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '5012345678900',
      'ean13',
      'Concurrent external product',
      null,
      null,
      '5012345678900'
    )$$,
  $$values (false, 'local_manual'::text)$$,
  'a later external save returns the existing manual winner'
);
select is(
  (select count(*) from public.product_barcodes where barcode = '5012345678900'),
  1::bigint,
  'manual/external retry leaves one barcode mapping'
);

select ok(
  to_regprocedure('public.create_product_for_barcode(uuid,text,text,text,text,text,text)') is not null,
  'the legacy external RPC signature remains exact and callable'
);
select ok(
  to_regprocedure('public.create_manual_product_for_barcode(uuid,text,text,text,text)') is not null,
  'the manual RPC signature remains exact and callable'
);
select is(
  pg_get_function_result(
    'public.create_product_for_barcode(uuid,text,text,text,text,text,text)'::regprocedure
  ),
  'TABLE(id uuid, shop_id uuid, name text, brand text, image_url text, source text, source_reference text, created_at timestamp with time zone, updated_at timestamp with time zone, was_created boolean)',
  'the legacy external RPC return shape remains unchanged'
);
select is(
  pg_get_function_result(
    'public.create_manual_product_for_barcode(uuid,text,text,text,text)'::regprocedure
  ),
  'TABLE(id uuid, shop_id uuid, name text, brand text, image_url text, source text, source_reference text, created_at timestamp with time zone, updated_at timestamp with time zone, was_created boolean)',
  'the manual RPC return shape remains unchanged'
);
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('create_product_for_barcode', 'create_manual_product_for_barcode')),
  2::bigint,
  'no unwanted public resolver overloads exist'
);

reset role;
select results_eq(
  $$select source, source_reference
    from public.catalog_products catalog
    join public.catalog_product_barcodes mapping on mapping.catalog_product_id = catalog.id
    where mapping.barcode = '5000112519945'$$,
  $$values ('open_food_facts'::text, '5000112519945'::text)$$,
  'compatibility external creation preserves global open_food_facts provenance'
);
select is(
  (select count(*) from public.catalog_product_barcodes where barcode = '5000112519945'),
  1::bigint,
  'first external save creates one global barcode mapping'
);
select results_eq(
  $$select source, source_reference
    from public.catalog_products catalog
    join public.catalog_product_barcodes mapping on mapping.catalog_product_id = catalog.id
    where mapping.barcode = '5012345678900'$$,
  $$values ('user_contributed'::text, null::text)$$,
  'manual creation records global user_contributed provenance'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select results_eq(
  $$select was_created from public.create_manual_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '1234567890123', 'ean13', 'Ignored replacement', null
    )$$,
  $$values (false)$$,
  'an existing shop barcode is reused instead of replacing its Product'
);
select ok(
  (select catalog_product_id is not null from public.products
    where id = 'aaaaaaaa-1111-1111-1111-111111111111'),
  'an existing Product with a NULL catalog identity is lazily attached'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select results_eq(
  $$select was_created from public.create_product_for_barcode(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      '5000112519945', 'ean13', 'External product', 'Brand', null, '5000112519945'
    )$$,
  $$values (true)$$,
  'a second shop creates its own Product for the existing global identity'
);

reset role;
select is(
  (select count(distinct catalog_product_id) from public.products
    where shop_id in ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
      and catalog_product_id = (
        select catalog_product_id from public.catalog_product_barcodes
        where barcode = '5000112519945'
      )),
  1::bigint,
  'both shops reuse exactly one CatalogProduct'
);
select is(
  (select count(distinct product.id) from public.products product
    join public.product_barcodes mapping on mapping.product_id = product.id
    where mapping.barcode = '5000112519945'),
  2::bigint,
  'both shops retain distinct shop-owned Product identities'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select throws_ok(
  $$select * from private.resolve_catalog_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '4006381333931', 'ean13',
      'Blocked', null, null, 'local_manual', null, 'user_contributed', null
    )$$,
  '42501',
  null,
  'authenticated clients cannot invoke the protected helper'
);
select throws_ok(
  $$insert into public.products (shop_id, name, source, catalog_product_id)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Forged identity', 'local_manual',
      'cccccccc-0000-0000-0000-000000000001'
    )$$,
  '42501',
  null,
  'direct Product inserts cannot forge CatalogProduct identity'
);
select throws_ok(
  $$update public.products
    set catalog_product_id = 'cccccccc-0000-0000-0000-000000000001'
    where id = 'aaaaaaaa-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'direct Product updates cannot reassign CatalogProduct identity'
);
select throws_ok(
  $$select * from public.create_manual_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '5901234123457', 'ean13', 'Conflict', null
    )$$,
  '23505',
  'Barcode is already linked to a conflicting CatalogProduct.',
  'a conflicting non-NULL CatalogProduct identity fails closed'
);

reset role;
select is(
  (select catalog_product_id from public.products
    where id = 'aaaaaaaa-2222-2222-2222-222222222222'),
  'cccccccc-0000-0000-0000-000000000002'::uuid,
  'a failed conflict leaves the existing CatalogProduct identity unchanged'
);
select results_eq(
  $$select batch.product_id, movement.batch_id
    from public.batches batch
    join public.inventory_movements movement on movement.batch_id = batch.id
    where batch.id = 'aaaaaaaa-6666-6666-6666-666666666666'$$,
  $$values (
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaa-6666-6666-6666-666666666666'::uuid
  )$$,
  'CatalogProduct attachment preserves Batch and InventoryMovement identities'
);
select ok(
  not exists (
    select 1 from unnest(
      (select proargnames from pg_proc
       where oid = 'public.create_manual_product_for_barcode(uuid,text,text,text,text)'::regprocedure)
    ) argument_name
    where argument_name in ('shop_product_source', 'catalog_source')
  ),
  'public callers cannot supply provenance parameters'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'products_shop_catalog_product_key'
  ),
  'one shop Product per non-NULL CatalogProduct is enforced'
);
select ok(
  pg_get_constraintdef(
    (select oid from pg_constraint
     where conrelid = 'public.catalog_products'::regclass
       and conname = 'catalog_products_source_check')
  ) like '%user_contributed%',
  'CatalogProduct source constraint permits explicit user contributions'
);

set local role anon;
select throws_ok(
  $$select * from public.create_product_for_barcode(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '4006381333931', 'ean13', 'Anonymous', null, null, null
    )$$,
  '42501',
  null,
  'anonymous callers cannot execute the compatibility RPC'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select * from public.create_manual_product_for_barcode(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      '4006381333931', 'ean13', 'Not a member', null
    )$$,
  '42501',
  'Shop membership is required.',
  'non-members cannot create Products for another shop'
);
select throws_ok(
  $$select * from public.catalog_products$$,
  '42501',
  null,
  'global CatalogProduct rows remain unreadable to authenticated clients'
);

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select lives_ok(
  $$select public.create_shop_with_owner('First shop')$$,
  'an authenticated user can create a first shop and membership'
);
select is(
  (
    select count(*)
    from public.shop_memberships
    where user_id = '33333333-3333-3333-3333-333333333333'
      and role = 'owner'
  ),
  1::bigint,
  'first-shop creation assigns the caller as owner'
);

select * from finish();
rollback;
