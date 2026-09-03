begin;
select plan(24);

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

insert into public.products (id, shop_id, name, source)
values
  ('aaaaaaaa-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Member product', 'local_manual'),
  ('bbbbbbbb-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Other product', 'local_manual');

insert into public.product_barcodes (id, shop_id, product_id, barcode, format, is_primary)
values
  (
    'aaaaaaaa-3333-3333-3333-333333333333',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'aaaaaaaa-1111-1111-1111-111111111111',
    '1234567890123',
    'ean13',
    true
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
  $$values ('Member product'::text)$$,
  'members read only their shop products'
);
select results_eq(
  $$select barcode from public.product_barcodes$$,
  $$values ('1234567890123'::text)$$,
  'members read only their shop barcodes'
);
select lives_ok(
  $$insert into public.products (id, shop_id, name, source)
    values (
      'aaaaaaaa-4444-4444-4444-444444444444',
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
    where product_id = 'aaaaaaaa-4444-4444-4444-444444444444'
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
  '23503',
  null,
  'barcode mappings cannot reference a product in another shop'
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
