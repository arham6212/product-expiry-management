-- Trust-boundary hardening for Cloudinary image contributions.
-- The preceding migration is already deployed with no contribution rows.

alter table public.catalog_product_image_contributions
  add column mime_type text not null,
  add column byte_size bigint not null,
  add column pixel_width integer not null,
  add column pixel_height integer not null,
  add constraint catalog_image_mime_type_check
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  add constraint catalog_image_byte_size_check
    check (byte_size between 1 and 5242880),
  add constraint catalog_image_dimensions_check
    check (
      pixel_width between 1 and 2048
      and pixel_height between 1 and 2048
    ),
  add constraint catalog_image_delivery_url_check
    check (delivery_url ~ '^https://res[.]cloudinary[.]com/');

create index catalog_product_image_contributions_shop_idx
  on public.catalog_product_image_contributions (shop_id);
create index catalog_product_image_contributions_uploader_idx
  on public.catalog_product_image_contributions (uploaded_by);
create index catalog_product_image_contributions_catalog_idx
  on public.catalog_product_image_contributions (catalog_product_id);

revoke all on table public.catalog_product_image_contributions
  from public, anon, authenticated;
grant select on table public.catalog_product_image_contributions to authenticated;
grant select, insert, update, delete
  on table public.catalog_product_image_contributions to service_role;

drop policy if exists "Users can view their own contributions"
  on public.catalog_product_image_contributions;
create policy "Members can view their own shop contributions"
on public.catalog_product_image_contributions
for select to authenticated
using (
  uploaded_by = (select auth.uid())
  and shop_id is not null
  and public.is_shop_member(shop_id)
);

create or replace function public.catalog_product_image_contributions_update_timestamp()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.catalog_product_image_contributions_update_timestamp()
  from public, anon, authenticated;

-- Retire the client-metadata RPC. Existing deployments keep the signature so a
-- stale client gets permission denied rather than an ambiguous function miss.
revoke all on function public.contribute_catalog_product_image(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated, service_role;

create or replace function public.record_verified_catalog_product_image_contribution(
  p_uploaded_by uuid,
  p_shop_id uuid,
  p_catalog_product_id uuid,
  p_provider_asset_id text,
  p_provider_public_id text,
  p_provider_version text,
  p_delivery_url text,
  p_mime_type text,
  p_byte_size bigint,
  p_pixel_width integer,
  p_pixel_height integer
)
returns table(contribution_id uuid, contribution_status text, delivery_url text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_existing public.catalog_product_image_contributions%rowtype;
begin
  if p_uploaded_by is null
     or p_shop_id is null
     or p_catalog_product_id is null then
    raise exception 'Verified contribution identity is required';
  end if;

  if p_mime_type not in ('image/jpeg', 'image/png', 'image/webp')
     or p_byte_size not between 1 and 5242880
     or p_pixel_width not between 1 and 2048
     or p_pixel_height not between 1 and 2048 then
    raise exception 'Verified image metadata is outside allowed limits';
  end if;

  if p_provider_asset_id is null or length(p_provider_asset_id) not between 1 and 512
     or p_provider_public_id is null or length(p_provider_public_id) not between 1 and 512
     or p_provider_version is null or length(p_provider_version) not between 1 and 64
     or p_delivery_url is null
     or length(p_delivery_url) > 2048
     or p_delivery_url !~ '^https://res[.]cloudinary[.]com/' then
    raise exception 'Verified provider metadata is invalid';
  end if;

  if not exists (
    select 1
    from public.shop_memberships sm
    where sm.shop_id = p_shop_id and sm.user_id = p_uploaded_by
  ) then
    raise exception 'Uploader is not a current shop member';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.shop_id = p_shop_id
      and p.catalog_product_id = p_catalog_product_id
  ) then
    raise exception 'Shop has no Product linked to this CatalogProduct';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('catalog-image:' || p_provider_asset_id, 0)
  );

  select * into v_existing
  from public.catalog_product_image_contributions c
  where c.storage_provider = 'cloudinary'
    and c.provider_asset_id = p_provider_asset_id
  for update;

  if found then
    if v_existing.uploaded_by is distinct from p_uploaded_by
       or v_existing.shop_id is distinct from p_shop_id
       or v_existing.catalog_product_id is distinct from p_catalog_product_id
       or v_existing.provider_public_id is distinct from p_provider_public_id then
      raise exception 'Provider asset is already bound to another contribution';
    end if;

    return query select v_existing.id, v_existing.status, v_existing.delivery_url;
    return;
  end if;

  return query
  insert into public.catalog_product_image_contributions (
    catalog_product_id, storage_provider, provider_asset_id,
    provider_public_id, provider_version, delivery_url, shop_id, uploaded_by,
    status, is_canonical, mime_type, byte_size, pixel_width, pixel_height
  ) values (
    p_catalog_product_id, 'cloudinary', p_provider_asset_id,
    p_provider_public_id, p_provider_version, p_delivery_url, p_shop_id,
    p_uploaded_by, 'pending', false, p_mime_type, p_byte_size,
    p_pixel_width, p_pixel_height
  )
  returning id, status, public.catalog_product_image_contributions.delivery_url;
end;
$$;

revoke all on function public.record_verified_catalog_product_image_contribution(
  uuid, uuid, uuid, text, text, text, text, text, bigint, integer, integer
) from public, anon, authenticated;
grant execute on function public.record_verified_catalog_product_image_contribution(
  uuid, uuid, uuid, text, text, text, text, text, bigint, integer, integer
) to service_role;

create or replace function public.set_catalog_product_canonical_image(
  p_contribution_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_contribution public.catalog_product_image_contributions%rowtype;
begin
  select * into v_contribution
  from public.catalog_product_image_contributions
  where id = p_contribution_id
  for update;

  if not found then
    raise exception 'Contribution not found';
  end if;
  if v_contribution.status = 'rejected' then
    raise exception 'A rejected contribution cannot become canonical';
  end if;

  perform 1 from public.catalog_products
  where id = v_contribution.catalog_product_id
  for update;

  update public.catalog_product_image_contributions
  set is_canonical = false
  where catalog_product_id = v_contribution.catalog_product_id
    and is_canonical;

  update public.catalog_product_image_contributions
  set status = 'approved', is_canonical = true
  where id = p_contribution_id;

  update public.catalog_products
  set image_url = v_contribution.delivery_url
  where id = v_contribution.catalog_product_id;
end;
$$;
revoke all on function public.set_catalog_product_canonical_image(uuid)
  from public, anon, authenticated;
grant execute on function public.set_catalog_product_canonical_image(uuid)
  to service_role;
