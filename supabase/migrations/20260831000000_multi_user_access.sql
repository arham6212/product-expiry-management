-- 1. Update shop_memberships constraints and roles

-- Temporarily drop the role check constraint to modify values
alter table public.shop_memberships drop constraint if exists shop_memberships_role_check;

-- Migrate existing 'staff' to 'worker'
update public.shop_memberships set role = 'worker' where role = 'staff';

-- Re-add the role check constraint with new roles
alter table public.shop_memberships add constraint shop_memberships_role_check check (role in ('owner', 'manager', 'worker'));

-- Enforce one shop per user
alter table public.shop_memberships add constraint shop_memberships_user_id_key unique (user_id);


-- 2. Create shop_invites table

create table public.shop_invites (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  code text not null unique check (char_length(btrim(code)) >= 6),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete cascade
);

create index shop_invites_shop_id_idx on public.shop_invites(shop_id);

alter table public.shop_invites enable row level security;

-- Only members can read the invites for their shop (could be restricted to just owners later, but for now owners definitely need it)
create policy "Owners can read shop invites"
on public.shop_invites for select
to authenticated
using (
  exists (
    select 1 from public.shop_memberships m
    where m.shop_id = shop_invites.shop_id
    and m.user_id = (select auth.uid())
    and m.role = 'owner'
  )
);

revoke all on table public.shop_invites from anon, authenticated;
grant select on table public.shop_invites to authenticated;


-- 3. Create shop_join_requests table

create table public.shop_join_requests (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

-- Only one pending request per user allowed
create unique index shop_join_requests_user_pending_idx on public.shop_join_requests(user_id) where status = 'pending';

create index shop_join_requests_shop_id_idx on public.shop_join_requests(shop_id);
create index shop_join_requests_user_id_idx on public.shop_join_requests(user_id);

alter table public.shop_join_requests enable row level security;

create policy "Users can read their own requests"
on public.shop_join_requests for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Owners can read requests for their shop"
on public.shop_join_requests for select
to authenticated
using (
  exists (
    select 1 from public.shop_memberships m
    where m.shop_id = shop_join_requests.shop_id
    and m.user_id = (select auth.uid())
    and m.role = 'owner'
  )
);

revoke all on table public.shop_join_requests from anon, authenticated;
grant select on table public.shop_join_requests to authenticated;


-- 4. RPCs for joining and reviewing

-- A helper function to generate a 6-character random alphanumeric code
create function public.generate_invite_code()
returns text
language sql
volatile
as $$
  select upper(substring(md5(random()::text) from 1 for 6));
$$;

create or replace function public.create_shop_with_owner(shop_name text)
returns public.shops
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_name text := regexp_replace(btrim(shop_name), '\s+', ' ', 'g');
  created_shop public.shops;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'Shop name must be 1 to 120 characters.';
  end if;

  if exists (select 1 from public.shop_memberships where user_id = caller_id) then
    raise exception using errcode = 'P0001', message = 'User is already a member of a shop.';
  end if;

  insert into public.shops (name)
  values (normalized_name)
  returning * into created_shop;

  insert into public.shop_memberships (shop_id, user_id, role)
  values (created_shop.id, caller_id, 'owner');

  -- Create an initial invite code
  insert into public.shop_invites (shop_id, code, created_by)
  values (created_shop.id, public.generate_invite_code(), caller_id);

  return created_shop;
end;
$$;

create function public.request_to_join_shop(join_code text)
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

  if exists (select 1 from public.shop_join_requests where user_id = caller_id and status = 'pending') then
    raise exception using errcode = 'P0001', message = 'User already has a pending join request.';
  end if;

  insert into public.shop_join_requests (shop_id, user_id, status)
  values (target_shop_id, caller_id, 'pending');

  return target_shop_id;
end;
$$;

create function public.review_join_request(request_id uuid, new_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  req public.shop_join_requests;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if new_status not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Invalid status.';
  end if;

  -- Lock the request row to prevent concurrent approvals
  select * into req
  from public.shop_join_requests
  where id = request_id
  for update;

  if req is null then
    raise exception using errcode = 'P0002', message = 'Request not found.';
  end if;
  if req.status != 'pending' then
    raise exception using errcode = 'P0001', message = 'Request is not pending.';
  end if;

  if not exists (
    select 1 from public.shop_memberships
    where shop_id = req.shop_id and user_id = caller_id and role = 'owner'
  ) then
    raise exception using errcode = '42501', message = 'Only shop owners can review requests.';
  end if;

  if new_status = 'approved' then
    if exists (select 1 from public.shop_memberships where user_id = req.user_id) then
      -- If the user already joined another shop, we reject this request instead.
      update public.shop_join_requests
      set status = 'rejected', reviewed_at = now(), reviewed_by = caller_id
      where id = request_id;
      raise exception using errcode = 'P0001', message = 'User is already a member of a shop.';
    end if;

    insert into public.shop_memberships (shop_id, user_id, role)
    values (req.shop_id, req.user_id, 'worker');
  end if;

  update public.shop_join_requests
  set status = new_status, reviewed_at = now(), reviewed_by = caller_id
  where id = request_id;
end;
$$;

create function public.rotate_shop_invite_code(target_shop_id uuid)
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

  -- Disable all existing invites
  update public.shop_invites
  set is_active = false
  where shop_id = target_shop_id;

  new_code := public.generate_invite_code();

  -- Create a new invite
  insert into public.shop_invites (shop_id, code, created_by)
  values (target_shop_id, new_code, caller_id);

  return new_code;
end;
$$;

create function public.update_shop_invite_status(target_shop_id uuid, target_is_active boolean)
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


revoke all on function public.generate_invite_code() from public, anon, authenticated;
revoke all on function public.request_to_join_shop(text) from public, anon, authenticated;
revoke all on function public.review_join_request(uuid, text) from public, anon, authenticated;
revoke all on function public.rotate_shop_invite_code(uuid) from public, anon, authenticated;
revoke all on function public.update_shop_invite_status(uuid, boolean) from public, anon, authenticated;

grant execute on function public.request_to_join_shop(text) to authenticated;
grant execute on function public.review_join_request(uuid, text) to authenticated;
grant execute on function public.rotate_shop_invite_code(uuid) to authenticated;
grant execute on function public.update_shop_invite_status(uuid, boolean) to authenticated;

-- Seed existing shops with an invite code to prevent issues
do $$
declare
  shop_record record;
  owner_id uuid;
begin
  for shop_record in select id from public.shops loop
    select user_id into owner_id from public.shop_memberships where shop_id = shop_record.id and role = 'owner' limit 1;
    if owner_id is not null then
      insert into public.shop_invites (shop_id, code, created_by)
      values (shop_record.id, public.generate_invite_code(), owner_id)
      on conflict (code) do nothing;
    end if;
  end loop;
end;
$$;

create function public.get_shop_pending_requests_with_users(target_shop_id uuid)
returns table (
  request_id uuid,
  user_id uuid,
  email text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = target_shop_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select r.id, r.user_id, u.email::text, r.status, r.created_at
  from public.shop_join_requests r
  join auth.users u on r.user_id = u.id
  where r.shop_id = target_shop_id and r.status = 'pending'
  order by r.created_at;
end;
$$;

create function public.get_shop_members_with_users(target_shop_id uuid)
returns table (
  user_id uuid,
  email text,
  role text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = target_shop_id and user_id = auth.uid() and role = 'owner'
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select m.user_id, u.email::text, m.role, m.created_at
  from public.shop_memberships m
  join auth.users u on m.user_id = u.id
  where m.shop_id = target_shop_id
  order by m.created_at;
end;
$$;

grant execute on function public.get_shop_pending_requests_with_users(uuid) to authenticated;
grant execute on function public.get_shop_members_with_users(uuid) to authenticated;
