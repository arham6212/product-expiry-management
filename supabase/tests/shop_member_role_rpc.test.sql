begin;
select plan(28);

insert into auth.users (id, email)
values
  ('61000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('61000000-0000-0000-0000-000000000002', 'co-owner@example.test'),
  ('61000000-0000-0000-0000-000000000003', 'manager@example.test'),
  ('61000000-0000-0000-0000-000000000004', 'worker@example.test'),
  ('61000000-0000-0000-0000-000000000005', 'other-owner@example.test'),
  ('61000000-0000-0000-0000-000000000006', 'other-worker@example.test');

insert into public.shops (id, name)
values
  ('62000000-0000-0000-0000-000000000001', 'Target Shop'),
  ('62000000-0000-0000-0000-000000000002', 'Other Shop');

insert into public.shop_memberships (shop_id, user_id, role)
values
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000001',
    'owner'
  ),
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000002',
    'owner'
  ),
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000003',
    'manager'
  ),
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000004',
    'worker'
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    '61000000-0000-0000-0000-000000000005',
    'owner'
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    '61000000-0000-0000-0000-000000000006',
    'worker'
  );

insert into public.shop_invites (
  id,
  shop_id,
  code,
  is_active,
  created_by,
  expires_at
)
values (
  '63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  'ROLE01',
  true,
  '61000000-0000-0000-0000-000000000001',
  now() + interval '1 day'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_shop_member_role(uuid, uuid, text)',
    'EXECUTE'
  ),
  'authenticated callers have execute permission on the role RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.update_shop_member_role(uuid, uuid, text)',
    'EXECUTE'
  ),
  'anonymous callers have no execute permission on the role RPC'
);

set local role anon;
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000004',
      'manager'
    )$$,
  '42501',
  null,
  'an anonymous caller cannot invoke the role RPC'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000001',
  true
);
select throws_ok(
  $$update public.shop_memberships
    set role = 'manager'
    where shop_id = '62000000-0000-0000-0000-000000000001'
      and user_id = '61000000-0000-0000-0000-000000000004'$$,
  '42501',
  null,
  'authenticated clients cannot update memberships directly'
);

select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000003',
  true
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000004',
      'manager'
    )$$,
  '42501',
  'Only Shop owners can change member roles.',
  'a manager cannot change member roles'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000003'
  ),
  'manager'::text,
  'a failed manager call leaves the manager role unchanged'
);

select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000004',
  true
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000003',
      'worker'
    )$$,
  '42501',
  'Only Shop owners can change member roles.',
  'a worker cannot change member roles'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000004'
  ),
  'worker'::text,
  'a failed worker call leaves the worker role unchanged'
);

select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000005',
  true
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000004',
      'manager'
    )$$,
  '42501',
  'Only Shop owners can change member roles.',
  'an owner from another Shop cannot change target-Shop roles'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000005'
  ),
  'owner'::text,
  'a failed cross-Shop call leaves the caller role unchanged'
);

select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000001',
  true
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000002',
      '61000000-0000-0000-0000-000000000006',
      'manager'
    )$$,
  '42501',
  'Only Shop owners can change member roles.',
  'an owner cannot mutate a membership in a Shop they do not own'
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000006',
      'manager'
    )$$,
  'P0002',
  'Target membership was not found in this Shop.',
  'a target membership from another Shop cannot be moved or changed'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000006'
  ),
  null,
  'the caller cannot read the other-Shop target through membership RLS'
);

select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000004',
      'administrator'
    )$$,
  '22023',
  'Role must be manager or worker.',
  'an unknown role is rejected'
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000004',
      'owner'
    )$$,
  '22023',
  'Role must be manager or worker.',
  'a target cannot be promoted to owner through the role RPC'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000004'
  ),
  'worker'::text,
  'invalid requested roles leave the target membership unchanged'
);

select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000001',
      'worker'
    )$$,
  '22023',
  'Owners cannot change their own role.',
  'an owner cannot demote themselves through the role RPC'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000001'
  ),
  'owner'::text,
  'the caller remains an owner after a self-demotion attempt'
);
select throws_ok(
  $$select public.update_shop_member_role(
      '62000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000002',
      'worker'
    )$$,
  '22023',
  'Owner memberships cannot be changed by this operation.',
  'an owner cannot alter another owner membership'
);
select is(
  (
    select membership.role
    from public.shop_memberships as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000002'
  ),
  null,
  'the caller cannot read another owner membership through direct member RLS'
);

select is(
  public.update_shop_member_role(
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000004',
    'manager'
  ),
  'manager'::text,
  'an owner can promote a worker to manager'
);
select is(
  (
    select membership.role
    from public.get_shop_members_with_users(
      '62000000-0000-0000-0000-000000000001'
    ) as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000004'
  ),
  'manager'::text,
  'the promoted role is visible through the existing member roster RPC'
);
select is(
  public.update_shop_member_role(
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000003',
    'worker'
  ),
  'worker'::text,
  'an owner can demote a manager to worker'
);
select is(
  (
    select membership.role
    from public.get_shop_members_with_users(
      '62000000-0000-0000-0000-000000000001'
    ) as membership
    where membership.user_id = '61000000-0000-0000-0000-000000000003'
  ),
  'worker'::text,
  'the demoted role is visible through the existing member roster RPC'
);
select is(
  (select count(*) from public.shop_memberships),
  1::bigint,
  'direct membership reads remain scoped to the authenticated caller'
);
select is(
  (
    select count(*)
    from public.shop_invites as invite
    where invite.id = '63000000-0000-0000-0000-000000000001'
      and invite.code = 'ROLE01'
      and invite.is_active
  ),
  1::bigint,
  'role changes do not alter the existing invite'
);
select set_config(
  'request.jwt.claim.sub',
  '61000000-0000-0000-0000-000000000004',
  true
);
select is(
  (
    with changed as (
      update public.shops
      set name = 'Manager private edit'
      where id = '62000000-0000-0000-0000-000000000001'
      returning id
    )
    select count(*) from changed
  ),
  0::bigint,
  'a promoted manager remains unable to update private Shop settings'
);

reset role;
select results_eq(
  $$select shop_id, user_id, role
    from public.shop_memberships
    order by shop_id, user_id$$,
  $$values
    (
      '62000000-0000-0000-0000-000000000001'::uuid,
      '61000000-0000-0000-0000-000000000001'::uuid,
      'owner'::text
    ),
    (
      '62000000-0000-0000-0000-000000000001'::uuid,
      '61000000-0000-0000-0000-000000000002'::uuid,
      'owner'::text
    ),
    (
      '62000000-0000-0000-0000-000000000001'::uuid,
      '61000000-0000-0000-0000-000000000003'::uuid,
      'worker'::text
    ),
    (
      '62000000-0000-0000-0000-000000000001'::uuid,
      '61000000-0000-0000-0000-000000000004'::uuid,
      'manager'::text
    ),
    (
      '62000000-0000-0000-0000-000000000002'::uuid,
      '61000000-0000-0000-0000-000000000005'::uuid,
      'owner'::text
    ),
    (
      '62000000-0000-0000-0000-000000000002'::uuid,
      '61000000-0000-0000-0000-000000000006'::uuid,
      'worker'::text
    )$$,
  'role changes preserve owners, membership identity, Shop ownership, and row count'
);

select * from finish();
rollback;
