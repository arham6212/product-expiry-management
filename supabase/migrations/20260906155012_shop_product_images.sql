-- Shop photos are usable immediately; catalog promotion remains separately curated.
-- Keep verified asset history so retries cannot undo a newer replacement.
create table public.shop_product_images (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  product_id uuid not null references public.products(id),
  uploaded_by uuid not null references auth.users(id),
  provider_asset_id text not null unique check (length(provider_asset_id) between 1 and 512),
  provider_public_id text not null check (length(provider_public_id) between 1 and 512),
  provider_version text not null check (length(provider_version) between 1 and 64),
  delivery_url text not null check (length(delivery_url) <= 2048 and delivery_url ~ '^https://res[.]cloudinary[.]com/'),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  byte_size bigint not null check (byte_size between 1 and 5242880),
  pixel_width integer not null check (pixel_width between 1 and 2048),
  pixel_height integer not null check (pixel_height between 1 and 2048),
  created_at timestamptz not null default now()
);
create index shop_product_images_product_idx on public.shop_product_images(product_id);
create index shop_product_images_shop_idx on public.shop_product_images(shop_id);
create index shop_product_images_uploader_idx on public.shop_product_images(uploaded_by);
alter table public.shop_product_images enable row level security;
revoke all on public.shop_product_images from public, anon, authenticated;
grant select on public.shop_product_images to authenticated;
grant all on public.shop_product_images to service_role;
create policy "Shop members read verified product photos" on public.shop_product_images
  for select to authenticated using (public.is_shop_member(shop_id));

create function public.record_verified_shop_product_image(
  p_uploaded_by uuid, p_shop_id uuid, p_product_id uuid,
  p_provider_asset_id text, p_provider_public_id text, p_provider_version text,
  p_delivery_url text, p_mime_type text, p_byte_size bigint,
  p_pixel_width integer, p_pixel_height integer
) returns table(image_id uuid, delivery_url text)
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_existing public.shop_product_images%rowtype;
  v_id uuid;
  v_url text;
begin
  if not exists (select 1 from public.shop_memberships
    where shop_id = p_shop_id and user_id = p_uploaded_by) then
    raise exception 'Uploader is not a current shop member';
  end if;
  select p.image_url into v_url from public.products p
    where p.id = p_product_id and p.shop_id = p_shop_id for update;
  if not found then raise exception 'Product does not belong to this shop'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shop-image:' || p_provider_asset_id, 0));
  select * into v_existing from public.shop_product_images
    where provider_asset_id = p_provider_asset_id;
  if found then
    if v_existing.shop_id is distinct from p_shop_id
       or v_existing.product_id is distinct from p_product_id
       or v_existing.uploaded_by is distinct from p_uploaded_by
       or v_existing.provider_public_id is distinct from p_provider_public_id
       or v_existing.provider_version is distinct from p_provider_version
       or v_existing.delivery_url is distinct from p_delivery_url then
      raise exception 'Asset is already bound to another photo';
    end if;
    -- A retry of an older upload must never restore it over the current photo.
    return query select v_existing.id, v_url;
    return;
  end if;
  insert into public.shop_product_images(
    shop_id, product_id, uploaded_by, provider_asset_id, provider_public_id,
    provider_version, delivery_url, mime_type, byte_size, pixel_width, pixel_height
  ) values (
    p_shop_id, p_product_id, p_uploaded_by, p_provider_asset_id, p_provider_public_id,
    p_provider_version, p_delivery_url, p_mime_type, p_byte_size, p_pixel_width, p_pixel_height
  ) returning id into v_id;
  update public.products set image_url = p_delivery_url
    where id = p_product_id and shop_id = p_shop_id;
  return query select v_id, p_delivery_url;
end;
$$;
revoke all on function public.record_verified_shop_product_image(
  uuid, uuid, uuid, text, text, text, text, text, bigint, integer, integer
) from public, anon, authenticated;
grant execute on function public.record_verified_shop_product_image(
  uuid, uuid, uuid, text, text, text, text, text, bigint, integer, integer
) to service_role;

-- Recover previously verified pending/approved shop uploads. No catalog record,
-- inventory identity, price, batch or movement is changed by this migration.
insert into public.shop_product_images(
  shop_id, product_id, uploaded_by, provider_asset_id, provider_public_id,
  provider_version, delivery_url, mime_type, byte_size, pixel_width, pixel_height, created_at
)
select c.shop_id, p.id, c.uploaded_by, c.provider_asset_id, c.provider_public_id,
  c.provider_version, c.delivery_url, c.mime_type, c.byte_size,
  c.pixel_width, c.pixel_height, c.created_at
from public.catalog_product_image_contributions c
join public.products p on p.shop_id = c.shop_id and p.catalog_product_id = c.catalog_product_id
where c.status in ('pending', 'approved') and c.storage_provider = 'cloudinary';
update public.products p set image_url = latest.delivery_url
from (select distinct on (product_id) product_id, delivery_url
      from public.shop_product_images order by product_id, created_at desc, id desc) latest
where p.id = latest.product_id;
