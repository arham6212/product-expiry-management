drop index if exists public.shop_invites_one_active_per_shop_idx;
drop function if exists public.get_active_shop_invite(uuid);

alter table public.shop_invites
drop constraint if exists shop_invites_expiry_after_creation_check;

create or replace function public.request_to_join_shop(join_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_shop_id uuid;
  normalized_code text := upper(btrim(join_code));
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  select shop_id into target_shop_id
  from public.shop_invites
  where code = normalized_code and is_active = true;

  if target_shop_id is null then
    raise exception using errcode = 'P0002', message = 'Invalid or expired join code.';
  end if;
  if exists (select 1 from public.shop_memberships where user_id = caller_id) then
    raise exception using errcode = 'P0001', message = 'User is already a member of a shop.';
  end if;
  if exists (
    select 1 from public.shop_join_requests where user_id = caller_id and status = 'pending'
  ) then
    raise exception using errcode = 'P0001', message = 'User already has a pending join request.';
  end if;

  insert into public.shop_join_requests (shop_id, user_id, status)
  values (target_shop_id, caller_id, 'pending');
  return target_shop_id;
end;
$$;

create or replace function public.rotate_shop_invite_code(target_shop_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  new_code text;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = target_shop_id and user_id = caller_id and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can rotate join codes.';
  end if;

  update public.shop_invites set is_active = false where shop_id = target_shop_id;
  new_code := public.generate_invite_code();
  insert into public.shop_invites (shop_id, code, created_by)
  values (target_shop_id, new_code, caller_id);
  return new_code;
end;
$$;

create or replace function public.update_shop_invite_status(
  target_shop_id uuid,
  target_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = target_shop_id and user_id = caller_id and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can update join codes.';
  end if;

  update public.shop_invites
  set is_active = target_is_active
  where shop_id = target_shop_id and is_active != target_is_active;
end;
$$;

alter table public.shop_invites drop column if exists expires_at;
