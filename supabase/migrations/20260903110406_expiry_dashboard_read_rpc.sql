create function public.get_expiry_dashboard(target_shop_id uuid)
returns table (
  reference_date date,
  shop_id uuid,
  batch_id uuid,
  product_id uuid,
  product_name text,
  product_brand text,
  expiry_date date,
  days_to_expiry integer,
  current_quantity integer,
  lot_number text,
  received_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  shop_time_zone text;
  shop_reference_date date;
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if not exists (
    select 1
    from public.shop_memberships as membership
    where membership.shop_id = target_shop_id
      and membership.user_id = caller_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Shop membership is required.';
  end if;

  select shop.time_zone
  into shop_time_zone
  from public.shops as shop
  where shop.id = target_shop_id;

  if shop_time_zone is null or not exists (
    select 1
    from pg_catalog.pg_timezone_names as zone
    where zone.name = shop_time_zone
  ) then
    raise exception using
      errcode = '22023',
      message = 'Shop timezone is invalid.';
  end if;

  shop_reference_date := (pg_catalog.now() at time zone shop_time_zone)::date;

  if not exists (
    select 1
    from public.batches as batch
    where batch.shop_id = target_shop_id
      and batch.current_quantity > 0
  ) then
    return query
    select
      shop_reference_date,
      target_shop_id,
      null::uuid,
      null::uuid,
      null::text,
      null::text,
      null::date,
      null::integer,
      null::integer,
      null::text,
      null::timestamptz;
    return;
  end if;

  return query
  select
    shop_reference_date,
    batch.shop_id,
    batch.id,
    product.id,
    product.name,
    product.brand,
    batch.expiry_date,
    case
      when batch.expiry_date is null then null
      else batch.expiry_date - shop_reference_date
    end,
    batch.current_quantity,
    batch.lot_number,
    batch.created_at
  from public.batches as batch
  join public.products as product
    on product.shop_id = batch.shop_id
   and product.id = batch.product_id
  where batch.shop_id = target_shop_id
    and batch.current_quantity > 0
  order by batch.expiry_date asc nulls last, batch.created_at, batch.id;
end;
$$;

revoke all on function public.get_expiry_dashboard(uuid)
  from public, anon, authenticated;
grant execute on function public.get_expiry_dashboard(uuid)
  to authenticated;
