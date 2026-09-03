-- Make shop invites time-bounded and guarantee one authoritative active invite.

alter table public.shop_invites
add column expires_at timestamptz;

update public.shop_invites
set expires_at = greatest(created_at + interval '7 days', now() + interval '7 days');

alter table public.shop_invites
alter column expires_at set default (now() + interval '7 days'),
alter column expires_at set not null;

alter table public.shop_invites
add constraint shop_invites_expiry_after_creation_check
check (expires_at > created_at);

update public.shop_invites
set is_active = false
where is_active
  and (expires_at <= now() or code !~ '^[A-Z0-9]{6}$');

with ranked_active_invites as (
  select
    id,
    row_number() over (
      partition by shop_id
      order by created_at desc, id desc
    ) as active_rank
  from public.shop_invites
  where is_active
)
update public.shop_invites as invite
set is_active = false
from ranked_active_invites as ranked
where invite.id = ranked.id
  and ranked.active_rank > 1;

create unique index shop_invites_one_active_per_shop_idx
on public.shop_invites (shop_id)
where is_active;

create function public.get_active_shop_invite(target_shop_id uuid)
returns setof public.shop_invites
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  if not exists (
    select 1
    from public.shop_memberships
    where shop_id = target_shop_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can read join codes.';
  end if;

  return query
  select invite.*
  from public.shop_invites as invite
  where invite.shop_id = target_shop_id
    and invite.is_active
    and invite.expires_at > now()
    and invite.code ~ '^[A-Z0-9]{6}$'
  order by invite.created_at desc, invite.id desc
  limit 1;
end;
$$;

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

  if exists (select 1 from public.shop_memberships where user_id = caller_id) then
    raise exception using errcode = 'P0001', message = 'User is already a member of a shop.';
  end if;

  if exists (
    select 1
    from public.shop_join_requests
    where user_id = caller_id and status = 'pending'
  ) then
    raise exception using errcode = 'P0001', message = 'User already has a pending join request.';
  end if;

  if normalized_code is null or normalized_code !~ '^[A-Z0-9]{6}$' then
    raise exception using errcode = 'P0002', message = 'Invalid or expired join code.';
  end if;

  select invite.shop_id
  into target_shop_id
  from public.shop_invites as invite
  where invite.code = normalized_code
    and invite.is_active
    and invite.expires_at > now()
  for update;

  if target_shop_id is null then
    raise exception using errcode = 'P0002', message = 'Invalid or expired join code.';
  end if;

  begin
    insert into public.shop_join_requests (shop_id, user_id, status)
    values (target_shop_id, caller_id, 'pending');
  exception
    when unique_violation then
      raise exception using
        errcode = 'P0001',
        message = 'User already has a pending join request.';
  end;

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
  attempt integer;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  if not exists (
    select 1
    from public.shop_memberships
    where shop_id = target_shop_id and user_id = caller_id and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can rotate join codes.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_shop_id::text, 0)
  );

  update public.shop_invites
  set is_active = false
  where shop_id = target_shop_id and is_active;

  for attempt in 1..5 loop
    new_code := public.generate_invite_code();
    begin
      insert into public.shop_invites (shop_id, code, created_by)
      values (target_shop_id, new_code, caller_id);
      return new_code;
    exception
      when unique_violation then
        null;
    end;
  end loop;

  raise exception using errcode = 'P0001', message = 'Could not generate a unique invite code.';
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
  selected_invite_id uuid;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  if target_is_active is null then
    raise exception using errcode = '22004', message = 'Invite status is required.';
  end if;

  if not exists (
    select 1
    from public.shop_memberships
    where shop_id = target_shop_id and user_id = caller_id and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can update join codes.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_shop_id::text, 0)
  );

  if not target_is_active then
    update public.shop_invites
    set is_active = false
    where shop_id = target_shop_id and is_active;
    return;
  end if;

  select invite.id
  into selected_invite_id
  from public.shop_invites as invite
  where invite.shop_id = target_shop_id
    and invite.expires_at > now()
    and invite.code ~ '^[A-Z0-9]{6}$'
  order by invite.created_at desc, invite.id desc
  limit 1
  for update;

  update public.shop_invites
  set is_active = false
  where shop_id = target_shop_id and is_active;

  if selected_invite_id is null then
    perform public.rotate_shop_invite_code(target_shop_id);
  else
    update public.shop_invites
    set is_active = true
    where id = selected_invite_id;
  end if;
end;
$$;

revoke all on function public.request_to_join_shop(text) from public, anon, authenticated;
revoke all on function public.rotate_shop_invite_code(uuid) from public, anon, authenticated;
revoke all on function public.update_shop_invite_status(uuid, boolean) from public, anon, authenticated;
revoke all on function public.get_active_shop_invite(uuid) from public, anon, authenticated;

grant execute on function public.request_to_join_shop(text) to authenticated;
grant execute on function public.rotate_shop_invite_code(uuid) to authenticated;
grant execute on function public.update_shop_invite_status(uuid, boolean) to authenticated;
grant execute on function public.get_active_shop_invite(uuid) to authenticated;
