begin;
select plan(27);

insert into auth.users (id, email)
values
  ('71000000-0000-0000-0000-000000000001', 'dashboard-owner@example.test'),
  ('71000000-0000-0000-0000-000000000002', 'dashboard-worker@example.test'),
  ('71000000-0000-0000-0000-000000000003', 'other-owner@example.test'),
  ('71000000-0000-0000-0000-000000000004', 'invalid-zone-owner@example.test'),
  ('71000000-0000-0000-0000-000000000005', 'empty-shop-owner@example.test');

insert into public.shops (id, name, time_zone)
values
  (
    '72000000-0000-0000-0000-000000000001',
    'Dashboard Shop',
    'Pacific/Kiritimati'
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    'Other Dashboard Shop',
    'Pacific/Honolulu'
  ),
  (
    '72000000-0000-0000-0000-000000000003',
    'Invalid Timezone Shop',
    'Not/A_Timezone'
  ),
  (
    '72000000-0000-0000-0000-000000000004',
    'Empty Dashboard Shop',
    'UTC'
  );

insert into public.shop_memberships (shop_id, user_id, role)
values
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    'owner'
  ),
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000002',
    'worker'
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    '71000000-0000-0000-0000-000000000003',
    'owner'
  ),
  (
    '72000000-0000-0000-0000-000000000003',
    '71000000-0000-0000-0000-000000000004',
    'owner'
  ),
  (
    '72000000-0000-0000-0000-000000000004',
    '71000000-0000-0000-0000-000000000005',
    'owner'
  );

insert into public.products (id, shop_id, name, brand, source)
values
  (
    '73000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001',
    'Urgent Product',
    'Pilot Brand',
    'local_manual'
  ),
  (
    '73000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000001',
    'Unknown Expiry Product',
    null,
    'local_manual'
  ),
  (
    '73000000-0000-0000-0000-000000000003',
    '72000000-0000-0000-0000-000000000002',
    'Other Shop Product',
    null,
    'local_manual'
  );

insert into public.batches (
  id,
  shop_id,
  product_id,
  expiry_date,
  lot_number,
  current_quantity,
  created_by,
  created_at,
  updated_at
)
values
  (
    '74000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000001',
    (now() at time zone 'Pacific/Kiritimati')::date - 1,
    'LOT-URGENT',
    5,
    '71000000-0000-0000-0000-000000000001',
    '2026-09-01 08:00:00+00',
    '2026-09-01 08:00:00+00'
  ),
  (
    '74000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000002',
    null,
    null,
    3,
    '71000000-0000-0000-0000-000000000001',
    '2026-09-01 09:00:00+00',
    '2026-09-01 09:00:00+00'
  ),
  (
    '74000000-0000-0000-0000-000000000003',
    '72000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000001',
    (now() at time zone 'Pacific/Kiritimati')::date - 2,
    'LOT-CLOSED',
    0,
    '71000000-0000-0000-0000-000000000001',
    '2026-09-01 07:00:00+00',
    '2026-09-01 07:00:00+00'
  ),
  (
    '74000000-0000-0000-0000-000000000004',
    '72000000-0000-0000-0000-000000000002',
    '73000000-0000-0000-0000-000000000003',
    (now() at time zone 'Pacific/Honolulu')::date + 8,
    'LOT-OTHER',
    7,
    '71000000-0000-0000-0000-000000000003',
    '2026-09-01 10:00:00+00',
    '2026-09-01 10:00:00+00'
  );

create temporary table captured_dashboard_dates (
  label text primary key,
  reference_date date not null
);
grant insert, select on table pg_temp.captured_dashboard_dates to authenticated;

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_expiry_dashboard(uuid)',
    'EXECUTE'
  ),
  'authenticated callers have execute permission on the dashboard RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_expiry_dashboard(uuid)',
    'EXECUTE'
  ),
  'anonymous callers have no execute permission on the dashboard RPC'
);
select ok(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.get_expiry_dashboard(uuid)'::regprocedure
  ),
  'the dashboard RPC is security definer'
);
select is(
  (
    select procedure.provolatile
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.get_expiry_dashboard(uuid)'::regprocedure
  ),
  's'::"char",
  'the read-only dashboard RPC is stable'
);
select ok(
  (
    select pg_catalog.array_to_string(procedure.proconfig, ',') like '%search_path=""%'
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.get_expiry_dashboard(uuid)'::regprocedure
  ),
  'the security-definer dashboard RPC pins an empty search path'
);

set local role anon;
select throws_ok(
  $$select * from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )$$,
  '42501',
  null,
  'an anonymous caller cannot execute the dashboard RPC'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000001',
  true
);

select is(
  (
    select count(*)
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
  ),
  2::bigint,
  'an owner receives every positive-quantity Batch in their Shop'
);
select results_eq(
  $$select
      shop_id,
      batch_id,
      product_id,
      product_name,
      product_brand,
      current_quantity,
      lot_number,
      received_at
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    where batch_id = '74000000-0000-0000-0000-000000000001'$$,
  $$values (
      '72000000-0000-0000-0000-000000000001'::uuid,
      '74000000-0000-0000-0000-000000000001'::uuid,
      '73000000-0000-0000-0000-000000000001'::uuid,
      'Urgent Product'::text,
      'Pilot Brand'::text,
      5::integer,
      'LOT-URGENT'::text,
      '2026-09-01 08:00:00+00'::timestamptz
    )$$,
  'the RPC returns only the dashboard Product and Batch display contract'
);
select is(
  (
    select days_to_expiry
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    where batch_id = '74000000-0000-0000-0000-000000000001'
  ),
  -1,
  'the signed day offset uses the Shop-local reference date'
);
select results_eq(
  $$select batch_id
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )$$,
  $$values
      ('74000000-0000-0000-0000-000000000001'::uuid),
      ('74000000-0000-0000-0000-000000000002'::uuid)$$,
  'dated urgent Batches sort before unknown-expiry Batches'
);
select is(
  (
    select count(*)
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    where batch_id = '74000000-0000-0000-0000-000000000003'
  ),
  0::bigint,
  'zero-quantity Batch history is excluded from the active dashboard'
);
select results_eq(
  $$select expiry_date, days_to_expiry
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    where batch_id = '74000000-0000-0000-0000-000000000002'$$,
  $$values (null::date, null::integer)$$,
  'historical unknown expiry remains explicit and is never fabricated'
);
select is(
  (
    select reference_date
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    limit 1
  ),
  (now() at time zone 'Pacific/Kiritimati')::date,
  'the reference date uses server time in the requested Shop timezone'
);
insert into pg_temp.captured_dashboard_dates (label, reference_date)
select 'target', reference_date
from public.get_expiry_dashboard(
  '72000000-0000-0000-0000-000000000001'
)
limit 1;

select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000002',
  true
);
select is(
  (
    select count(*)
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
  ),
  2::bigint,
  'a worker has the same Shop-scoped dashboard read access'
);
select is(
  (
    select count(*)
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000001'
    )
    where shop_id <> '72000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'a worker never receives rows from another Shop'
);
select throws_ok(
  $$select * from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000002'
    )$$,
  '42501',
  'Shop membership is required.',
  'supplying another Shop ID cannot bypass membership authorization'
);

select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000003',
  true
);
select results_eq(
  $$select shop_id, batch_id, product_name
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000002'
    )$$,
  $$values (
      '72000000-0000-0000-0000-000000000002'::uuid,
      '74000000-0000-0000-0000-000000000004'::uuid,
      'Other Shop Product'::text
    )$$,
  'the other owner receives only their own Shop dashboard row'
);
select is(
  (
    select reference_date
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000002'
    )
  ),
  (now() at time zone 'Pacific/Honolulu')::date,
  'a second Shop derives today independently in its configured timezone'
);
insert into pg_temp.captured_dashboard_dates (label, reference_date)
select 'other', reference_date
from public.get_expiry_dashboard(
  '72000000-0000-0000-0000-000000000002'
);
select is(
  (
    select days_to_expiry
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000002'
    )
  ),
  8,
  'day offsets are relative to each Shop rather than the UTC date'
);

reset role;
select is(
  (
    select target.reference_date - other_shop.reference_date
    from pg_temp.captured_dashboard_dates as target
    cross join pg_temp.captured_dashboard_dates as other_shop
    where target.label = 'target'
      and other_shop.label = 'other'
  ),
  1,
  'timezone boundary fixtures produce different Shop-local calendar dates'
);
select ok(
  exists (
    select 1
    from pg_temp.captured_dashboard_dates as captured
    where captured.reference_date <> (now() at time zone 'UTC')::date
  ),
  'at least one asserted Shop-local date differs from the server UTC date'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000005',
  true
);
select results_eq(
  $$select reference_date, shop_id, batch_id, current_quantity
    from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000004'
    )$$,
  $$values (
      (now() at time zone 'UTC')::date,
      '72000000-0000-0000-0000-000000000004'::uuid,
      null::uuid,
      null::integer
    )$$,
  'an empty dashboard still returns its authoritative reference-date metadata'
);

select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000004',
  true
);
select throws_ok(
  $$select * from public.get_expiry_dashboard(
      '72000000-0000-0000-0000-000000000003'
    )$$,
  '22023',
  'Shop timezone is invalid.',
  'an invalid persisted Shop timezone fails explicitly'
);

select set_config(
  'request.jwt.claim.sub',
  '71000000-0000-0000-0000-000000000003',
  true
);
select is(
  (select count(*) from public.batches),
  1::bigint,
  'existing Batch RLS still exposes only the caller Shop'
);
select is(
  (select count(*) from public.products),
  1::bigint,
  'existing Product RLS still exposes only the caller Shop'
);

reset role;
select is(
  (select count(*) from public.batches),
  4::bigint,
  'dashboard reads do not mutate Batch history'
);
select is(
  (select count(*) from public.inventory_movements),
  0::bigint,
  'dashboard reads do not create inventory movements'
);

select * from finish();
rollback;
