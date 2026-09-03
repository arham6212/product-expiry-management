begin;
select plan(10);

insert into auth.users (id, email)
values
  ('51000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('51000000-0000-0000-0000-000000000002', 'manager@example.test'),
  ('51000000-0000-0000-0000-000000000003', 'worker@example.test'),
  ('51000000-0000-0000-0000-000000000004', 'other-owner@example.test');

insert into public.shops (id, name, time_zone, currency_code)
values
  (
    '52000000-0000-0000-0000-000000000001',
    'Private Shop',
    'Asia/Qatar',
    'QAR'
  ),
  (
    '52000000-0000-0000-0000-000000000002',
    'Other Shop',
    'UTC',
    'USD'
  );

insert into public.shop_memberships (shop_id, user_id, role)
values
  (
    '52000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000001',
    'owner'
  ),
  (
    '52000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000002',
    'manager'
  ),
  (
    '52000000-0000-0000-0000-000000000001',
    '51000000-0000-0000-0000-000000000003',
    'worker'
  ),
  (
    '52000000-0000-0000-0000-000000000002',
    '51000000-0000-0000-0000-000000000004',
    'owner'
  );

set local role anon;
select throws_ok(
  $$update public.shops
    set name = 'Anonymous edit'
    where id = '52000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'anonymous users cannot update private Shop settings'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  (
    with changed as (
      update public.shops
      set name = 'Owner Updated Shop',
          time_zone = 'Asia/Dubai',
          currency_code = 'AED'
      where id = '52000000-0000-0000-0000-000000000001'
      returning id
    )
    select count(*) from changed
  ),
  1::bigint,
  'an owner can update private settings for their Shop'
);
select results_eq(
  $$select name, time_zone, currency_code from public.shops$$,
  $$values ('Owner Updated Shop'::text, 'Asia/Dubai'::text, 'AED'::text)$$,
  'the owner reads their updated Shop settings'
);

select set_config(
  'request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000002',
  true
);
select is(
  (
    with changed as (
      update public.shops
      set name = 'Manager edit'
      where id = '52000000-0000-0000-0000-000000000001'
      returning id
    )
    select count(*) from changed
  ),
  0::bigint,
  'a manager cannot update private Shop settings'
);
select results_eq(
  $$select name from public.shops$$,
  $$values ('Owner Updated Shop'::text)$$,
  'a manager retains member read access to their Shop'
);

select set_config(
  'request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000003',
  true
);
select is(
  (
    with changed as (
      update public.shops
      set name = 'Worker edit'
      where id = '52000000-0000-0000-0000-000000000001'
      returning id
    )
    select count(*) from changed
  ),
  0::bigint,
  'a worker cannot update private Shop settings'
);
select results_eq(
  $$select name from public.shops$$,
  $$values ('Owner Updated Shop'::text)$$,
  'a worker retains member read access to their Shop'
);

select set_config(
  'request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000004',
  true
);
select is(
  (
    with changed as (
      update public.shops
      set name = 'Cross-shop edit'
      where id = '52000000-0000-0000-0000-000000000001'
      returning id
    )
    select count(*) from changed
  ),
  0::bigint,
  'an owner from another Shop cannot update private settings'
);
select results_eq(
  $$select name from public.shops$$,
  $$values ('Other Shop'::text)$$,
  'the cross-shop owner retains read access only to their own Shop'
);

reset role;
select is(
  (
    select name
    from public.shops
    where id = '52000000-0000-0000-0000-000000000001'
  ),
  'Owner Updated Shop'::text,
  'denied updates leave the private Shop settings unchanged'
);

select * from finish();
rollback;
