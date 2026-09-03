create function public.update_shop_member_role(
  target_shop_id uuid,
  target_user_id uuid,
  requested_role text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_membership public.shop_memberships%rowtype;
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if requested_role is null or requested_role not in ('manager', 'worker') then
    raise exception using
      errcode = '22023',
      message = 'Role must be manager or worker.';
  end if;

  if not exists (
    select 1
    from public.shop_memberships as caller_membership
    where caller_membership.shop_id = target_shop_id
      and caller_membership.user_id = caller_id
      and caller_membership.role = 'owner'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only Shop owners can change member roles.';
  end if;

  select target_membership_row.*
  into target_membership
  from public.shop_memberships as target_membership_row
  where target_membership_row.shop_id = target_shop_id
    and target_membership_row.user_id = target_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Target membership was not found in this Shop.';
  end if;

  if target_user_id = caller_id then
    raise exception using
      errcode = '22023',
      message = 'Owners cannot change their own role.';
  end if;

  if target_membership.role = 'owner' then
    raise exception using
      errcode = '22023',
      message = 'Owner memberships cannot be changed by this operation.';
  end if;

  update public.shop_memberships as membership
  set role = requested_role
  where membership.shop_id = target_shop_id
    and membership.user_id = target_user_id;

  return requested_role;
end;
$$;

revoke all on function public.update_shop_member_role(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.update_shop_member_role(uuid, uuid, text)
  to authenticated;
