drop policy if exists "Members can update their shops" on public.shops;

create policy "Owners can update their shops"
on public.shops for update
to authenticated
using (
  exists (
    select 1
    from public.shop_memberships membership
    where membership.shop_id = shops.id
      and membership.user_id = (select auth.uid())
      and membership.role = 'owner'
  )
)
with check (
  exists (
    select 1
    from public.shop_memberships membership
    where membership.shop_id = shops.id
      and membership.user_id = (select auth.uid())
      and membership.role = 'owner'
  )
);
