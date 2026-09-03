begin;
select plan(19);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'owner-invite@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'worker-invite@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'other-worker@example.test');

insert into public.shops (id, name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Invite Test Shop');

insert into public.shop_memberships (shop_id, user_id, role)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'owner'
);

insert into public.shop_invites (
  id,
  shop_id,
  code,
  is_active,
  created_at,
  created_by,
  expires_at
)
values (
  'aaaaaaaa-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'ABC123',
  true,
  now(),
  '11111111-1111-1111-1111-111111111111',
  now() + interval '7 days'
);

select has_column('public', 'shop_invites', 'expires_at', 'invites have an expiry instant');
select has_index(
  'public',
  'shop_invites',
  'shop_invites_one_active_per_shop_idx',
  'one-active-invite index exists'
);
select throws_ok(
  $$insert into public.shop_invites (shop_id, code, created_by, expires_at)
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'DEF456',
      '11111111-1111-1111-1111-111111111111',
      now() + interval '7 days'
    )$$,
  '23505',
  null,
  'the database rejects a second active invite'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$select code from public.get_active_shop_invite(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    )$$,
  $$values ('ABC123'::text)$$,
  'the owner reads the active unexpired invite using server time'
);

select lives_ok(
  $$select public.update_shop_invite_status(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false
    )$$,
  'the owner can disable invitations'
);
select is(
  (
    select count(*)
    from public.shop_invites
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and is_active
  ),
  0::bigint,
  'disabling leaves no active invite'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select throws_ok(
  $$select public.request_to_join_shop('ABC123')$$,
  'P0002',
  'Invalid or expired join code.',
  'a revoked invite is rejected by the server'
);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select lives_ok(
  $$select public.update_shop_invite_status(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true
    )$$,
  'the owner can re-enable the newest usable invite'
);
select is(
  (
    select count(*)
    from public.shop_invites
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and is_active
  ),
  1::bigint,
  're-enabling restores exactly one invite'
);
select is(
  (
    select code
    from public.shop_invites
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and is_active
  ),
  'ABC123'::text,
  're-enabling selects the current invite deterministically'
);

select lives_ok(
  $$select public.update_shop_invite_status(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false
    )$$,
  'the current invite can be disabled before expiry validation'
);

reset role;
insert into public.shop_invites (
  shop_id,
  code,
  is_active,
  created_at,
  created_by,
  expires_at
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'EXP123',
  true,
  now() - interval '8 days',
  '11111111-1111-1111-1111-111111111111',
  now() - interval '1 day'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select throws_ok(
  $$select public.request_to_join_shop('EXP123')$$,
  'P0002',
  'Invalid or expired join code.',
  'an expired active row is still rejected by the server'
);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select lives_ok(
  $$select public.rotate_shop_invite_code('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  'the owner can rotate to a new invite'
);
select is(
  (
    select count(*)
    from public.shop_invites
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and is_active
  ),
  1::bigint,
  'rotation leaves exactly one active invite'
);
select is(
  (
    select is_active
    from public.shop_invites
    where code = 'EXP123'
  ),
  false,
  'rotation revokes the expired historical invite'
);
select ok(
  (
    select expires_at > now()
    from public.shop_invites
    where shop_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and is_active
  ),
  'the rotated invite has a future expiry'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select results_eq(
  $$select public.request_to_join_shop(
      lower((select code from public.shop_invites where is_active))
    )$$,
  $$values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)$$,
  'manual lowercase input is normalized by the server'
);
select throws_ok(
  $$select public.request_to_join_shop(
      (select code from public.shop_invites where is_active)
    )$$,
  'P0001',
  'User already has a pending join request.',
  'duplicate pending requests are rejected'
);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select throws_ok(
  $$select public.request_to_join_shop(
      (select code from public.shop_invites where is_active)
    )$$,
  'P0001',
  'User is already a member of a shop.',
  'existing members cannot request another membership'
);

select * from finish();
rollback;
