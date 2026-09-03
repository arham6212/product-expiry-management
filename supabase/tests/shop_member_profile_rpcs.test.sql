begin;
select plan(4);

insert into auth.users (id, email)
values
  ('41111111-1111-1111-1111-111111111111', 'profile-owner@example.test'),
  ('42222222-2222-2222-2222-222222222222', 'profile-member@example.test'),
  ('43333333-3333-3333-3333-333333333333', 'profile-requester@example.test');

insert into public.shops (id, name)
values ('4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Profile RPC Test Shop');

insert into public.shop_memberships (shop_id, user_id, role, created_at)
values
  (
    '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '41111111-1111-1111-1111-111111111111',
    'owner',
    '2026-08-30 08:00:00+00'::timestamptz
  ),
  (
    '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '42222222-2222-2222-2222-222222222222',
    'worker',
    '2026-08-30 09:00:00+00'::timestamptz
  );

insert into public.shop_join_requests (
  id,
  shop_id,
  user_id,
  status,
  created_at
)
values (
  '4bbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '43333333-3333-3333-3333-333333333333',
  'pending',
  '2026-08-30 10:00:00+00'::timestamptz
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '41111111-1111-1111-1111-111111111111',
  true
);

select results_eq(
  $$
    select user_id, email, role, created_at
    from public.get_shop_members_with_users(
      '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    )
  $$,
  $$
    values
      (
        '41111111-1111-1111-1111-111111111111'::uuid,
        'profile-owner@example.test'::text,
        'owner'::text,
        '2026-08-30 08:00:00+00'::timestamptz
      ),
      (
        '42222222-2222-2222-2222-222222222222'::uuid,
        'profile-member@example.test'::text,
        'worker'::text,
        '2026-08-30 09:00:00+00'::timestamptz
      )
  $$,
  'an authenticated owner can load member user profiles'
);

select results_eq(
  $$
    select request_id, user_id, email, status, created_at
    from public.get_shop_pending_requests_with_users(
      '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    )
  $$,
  $$
    values (
      '4bbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
      '43333333-3333-3333-3333-333333333333'::uuid,
      'profile-requester@example.test'::text,
      'pending'::text,
      '2026-08-30 10:00:00+00'::timestamptz
    )
  $$,
  'an authenticated owner can load pending-request user profiles'
);

select set_config(
  'request.jwt.claim.sub',
  '42222222-2222-2222-2222-222222222222',
  true
);

select throws_ok(
  $$
    select *
    from public.get_shop_members_with_users(
      '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    )
  $$,
  'P0001',
  'Not authorized',
  'an authenticated non-owner cannot load member user profiles'
);

select throws_ok(
  $$
    select *
    from public.get_shop_pending_requests_with_users(
      '4aaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    )
  $$,
  'P0001',
  'Not authorized',
  'an authenticated non-owner cannot load pending-request user profiles'
);

select * from finish();
rollback;
