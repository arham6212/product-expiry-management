begin;
select plan(31);

insert into auth.users (id, email)
values
  ('44444444-4444-4444-4444-444444444444', 'receiver@example.test'),
  ('55555555-5555-5555-5555-555555555555', 'other-receiver@example.test');

insert into public.shops (id, name)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Receiving shop'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Other receiving shop');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '44444444-4444-4444-4444-444444444444', 'owner'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '55555555-5555-5555-5555-555555555555', 'owner');

insert into public.products (id, shop_id, name, source)
values
  (
    'cccccccc-1111-1111-1111-111111111111',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'Receiving product',
    'local_manual'
  ),
  (
    'dddddddd-2222-2222-2222-222222222222',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'Other receiving product',
    'local_manual'
  );

-- Historical unknown-expiry stock remains valid data. B02 changes only the
-- manual receiving function, not the nullable storage model.
insert into public.batches (
  id, shop_id, product_id, expiry_date, current_quantity, created_by
) values (
  'cccccccc-3333-3333-3333-333333333333',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'cccccccc-1111-1111-1111-111111111111',
  null,
  4,
  '44444444-4444-4444-4444-444444444444'
);

select has_table('public', 'batches', 'batches table exists');
select has_table('public', 'inventory_movements', 'inventory movements table exists');
select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'batches'
      and column_name = 'expiry_date'
  ),
  'YES',
  'the expiry column stays nullable for historical inventory'
);
select has_index(
  'public',
  'inventory_movements',
  'inventory_movements_shop_idempotency_key',
  'receiving idempotency has a database uniqueness boundary'
);

select throws_ok(
  $$insert into public.batches (
      shop_id, product_id, current_quantity, created_by
    ) values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'dddddddd-2222-2222-2222-222222222222',
      1,
      '44444444-4444-4444-4444-444444444444'
    )$$,
  '23503',
  null,
  'a batch cannot reference a Product from another shop'
);

set local role anon;
select throws_ok(
  $$select * from public.batches$$,
  '42501',
  null,
  'anonymous users cannot read batches'
);
select throws_ok(
  $$select * from public.inventory_movements$$,
  '42501',
  null,
  'anonymous users cannot read inventory movements'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      20,
      '2026-09-12',
      'LOT-7',
      'receive-anonymous'
    )$$,
  '42501',
  null,
  'anonymous users cannot execute receiving'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$select expiry_date, current_quantity
    from public.batches
    where id = 'cccccccc-3333-3333-3333-333333333333'$$,
  $$values (null::date, 4::integer)$$,
  'a member can still read unchanged historical unknown-expiry stock'
);

select throws_ok(
  $$insert into public.batches (
      shop_id, product_id, current_quantity, created_by
    ) values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      20,
      '44444444-4444-4444-4444-444444444444'
    )$$,
  '42501',
  null,
  'authenticated clients cannot insert batches directly'
);
select throws_ok(
  $$insert into public.inventory_movements (
      shop_id, batch_id, movement_type, quantity_delta, created_by, idempotency_key
    ) values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      gen_random_uuid(),
      'received',
      20,
      '44444444-4444-4444-4444-444444444444',
      'direct-write'
    )$$,
  '42501',
  null,
  'authenticated clients cannot insert movements directly'
);
select throws_ok(
  $$update public.batches set current_quantity = 99$$,
  '42501',
  null,
  'authenticated clients cannot update batches directly'
);
select throws_ok(
  $$delete from public.inventory_movements$$,
  '42501',
  null,
  'authenticated clients cannot delete movement history'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      'dddddddd-2222-2222-2222-222222222222',
      20,
      '2026-09-12',
      null,
      'receive-other-shop'
    )$$,
  '42501',
  null,
  'a member cannot receive into another shop'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'dddddddd-2222-2222-2222-222222222222',
      20,
      '2026-09-12',
      null,
      'receive-wrong-product'
    )$$,
  'P0002',
  null,
  'a Product from another shop is unavailable to receiving'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      0,
      '2026-09-12',
      null,
      'receive-invalid-quantity'
    )$$,
  '22023',
  null,
  'zero quantity is rejected before persistence'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      20,
      null,
      null,
      'receive-missing-expiry'
    )$$,
  '22023',
  'Expiry date is required.',
  'missing expiry is rejected before persistence'
);
select results_eq(
  $$select
      (select count(*) from public.batches),
      (select count(*) from public.inventory_movements)$$,
  $$values (1::bigint, 0::bigint)$$,
  'failed requests leave no new batch or movement'
);

select results_eq(
  $$select was_duplicate from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      20,
      '2026-09-12',
      '  LOT-7  ',
      'receive-1'
    )$$,
  $$values (false)$$,
  'first receiving request creates a receipt'
);
select is(
  (select count(*) from public.batches),
  2::bigint,
  'receiving creates exactly one batch'
);
select is(
  (select count(*) from public.inventory_movements),
  1::bigint,
  'receiving creates exactly one movement'
);
select results_eq(
  $$select batch.id, movement.batch_id
    from public.batches batch
    join public.inventory_movements movement
      on movement.shop_id = batch.shop_id and movement.batch_id = batch.id$$,
  $$select id, id
    from public.batches
    where id <> 'cccccccc-3333-3333-3333-333333333333'$$,
  'the received movement references the atomically created batch'
);
select results_eq(
  $$select expiry_date, lot_number, current_quantity
    from public.batches
    where expiry_date is not null$$,
  $$values ('2026-09-12'::date, 'LOT-7'::text, 20::integer)$$,
  'expiry, normalized lot, and initial quantity are persisted'
);
select results_eq(
  $$select was_duplicate from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      20,
      '2026-09-12',
      'LOT-7',
      'receive-1'
    )$$,
  $$values (true)$$,
  'an exact retry returns the existing receipt'
);
select results_eq(
  $$select
      (select count(*) from public.batches),
      (select count(*) from public.inventory_movements)$$,
  $$values (2::bigint, 1::bigint)$$,
  'an exact retry does not duplicate stock'
);
select throws_ok(
  $$select * from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      21,
      '2026-09-12',
      'LOT-7',
      'receive-1'
    )$$,
  '23505',
  null,
  'changed input cannot reuse an idempotency key'
);
select results_eq(
  $$select was_duplicate, batch_expiry_date, batch_lot_number
    from public.receive_product_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'cccccccc-1111-1111-1111-111111111111',
      5,
      '2026-10-01',
      '   ',
      'receive-blank-lot'
    )$$,
  $$values (false, '2026-10-01'::date, null::text)$$,
  'required expiry and blank-as-null lot are accepted'
);

select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', true);
select is(
  (select count(*) from public.batches),
  0::bigint,
  'another shop member cannot read the first shop batches'
);
select is(
  (select count(*) from public.inventory_movements),
  0::bigint,
  'another shop member cannot read the first shop movements'
);
select results_eq(
  $$select was_duplicate from public.receive_product_stock(
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      'dddddddd-2222-2222-2222-222222222222',
      3,
      '2026-09-30',
      null,
      'receive-other-member'
    )$$,
  $$values (false)$$,
  'a member can receive a Product in their own shop'
);
select is(
  (select count(*) from public.batches),
  1::bigint,
  'the other member reads only their own receiving rows'
);

select * from finish();
rollback;
