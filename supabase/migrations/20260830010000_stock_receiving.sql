create table public.batches (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  product_id uuid not null,
  expiry_date date,
  lot_number text check (
    lot_number is null or char_length(btrim(lot_number)) between 1 and 120
  ),
  current_quantity integer not null check (
    current_quantity between 0 and 2147483647
  ),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint batches_shop_id_id_key unique (shop_id, id),
  constraint batches_product_shop_fkey
    foreign key (shop_id, product_id)
    references public.products(shop_id, id)
    on delete restrict
);

create index batches_shop_product_idx on public.batches(shop_id, product_id);
create index batches_shop_expiry_idx on public.batches(shop_id, expiry_date);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  batch_id uuid not null,
  movement_type text not null check (
    movement_type in ('received', 'sold', 'disposed', 'returned', 'adjusted')
  ),
  quantity_delta integer not null,
  occurred_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  idempotency_key text not null check (
    char_length(btrim(idempotency_key)) between 1 and 200
  ),
  constraint inventory_movements_batch_shop_fkey
    foreign key (shop_id, batch_id)
    references public.batches(shop_id, id)
    on delete restrict,
  constraint inventory_movements_quantity_direction check (
    (movement_type = 'received' and quantity_delta > 0)
    or (movement_type in ('sold', 'disposed', 'returned') and quantity_delta < 0)
    or (movement_type = 'adjusted' and quantity_delta <> 0)
  ),
  constraint inventory_movements_shop_idempotency_key unique (shop_id, idempotency_key)
);

create index inventory_movements_shop_batch_idx
  on public.inventory_movements(shop_id, batch_id);
create index inventory_movements_shop_occurred_idx
  on public.inventory_movements(shop_id, occurred_at desc);

create trigger batches_set_updated_at
before update on public.batches
for each row execute function public.set_updated_at();

alter table public.batches enable row level security;
alter table public.inventory_movements enable row level security;

revoke all on table public.batches from anon, authenticated;
revoke all on table public.inventory_movements from anon, authenticated;

grant select on table public.batches to authenticated;
grant select on table public.inventory_movements to authenticated;

create policy "Members can read batches"
on public.batches for select
to authenticated
using ((select public.is_shop_member(shop_id)));

create policy "Members can read inventory movements"
on public.inventory_movements for select
to authenticated
using ((select public.is_shop_member(shop_id)));

create function public.receive_product_stock(
  target_shop_id uuid,
  target_product_id uuid,
  received_quantity integer,
  target_expiry_date date,
  target_lot_number text,
  request_idempotency_key text
)
returns table (
  batch_id uuid,
  batch_shop_id uuid,
  batch_product_id uuid,
  batch_expiry_date date,
  batch_lot_number text,
  batch_current_quantity integer,
  batch_created_at timestamptz,
  batch_updated_at timestamptz,
  movement_id uuid,
  movement_shop_id uuid,
  movement_batch_id uuid,
  movement_type text,
  movement_quantity_delta integer,
  movement_occurred_at timestamptz,
  movement_created_at timestamptz,
  movement_idempotency_key text,
  was_duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_lot_number text := nullif(
    regexp_replace(btrim(target_lot_number), '\s+', ' ', 'g'),
    ''
  );
  normalized_idempotency_key text := btrim(request_idempotency_key);
  existing_batch public.batches;
  existing_movement public.inventory_movements;
  created_batch public.batches;
  created_movement public.inventory_movements;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if not public.is_shop_member(target_shop_id) then
    raise exception using errcode = '42501', message = 'Shop membership is required.';
  end if;
  if target_product_id is null or not exists (
    select 1
    from public.products product
    where product.shop_id = target_shop_id
      and product.id = target_product_id
  ) then
    raise exception using errcode = 'P0002', message = 'Product is unavailable in this shop.';
  end if;
  if received_quantity is null or received_quantity <= 0 then
    raise exception using errcode = '22023', message = 'Quantity must be greater than zero.';
  end if;
  if normalized_idempotency_key is null
    or char_length(normalized_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'Idempotency key must be 1 to 200 characters.';
  end if;
  if normalized_lot_number is not null and char_length(normalized_lot_number) > 120 then
    raise exception using errcode = '22023', message = 'Lot number must be 120 characters or less.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_shop_id::text || ':' || normalized_idempotency_key, 0)
  );

  select movement.*
  into existing_movement
  from public.inventory_movements movement
  where movement.shop_id = target_shop_id
    and movement.idempotency_key = normalized_idempotency_key;

  if found then
    select batch.*
    into strict existing_batch
    from public.batches batch
    where batch.shop_id = existing_movement.shop_id
      and batch.id = existing_movement.batch_id;

    if existing_batch.product_id is distinct from target_product_id
      or existing_batch.expiry_date is distinct from target_expiry_date
      or existing_batch.lot_number is distinct from normalized_lot_number
      or existing_movement.movement_type is distinct from 'received'
      or existing_movement.quantity_delta is distinct from received_quantity then
      raise exception using
        errcode = '23505',
        message = 'Idempotency key was already used with different receiving input.';
    end if;

    return query
    select existing_batch.id, existing_batch.shop_id, existing_batch.product_id,
      existing_batch.expiry_date, existing_batch.lot_number,
      existing_batch.current_quantity, existing_batch.created_at,
      existing_batch.updated_at, existing_movement.id,
      existing_movement.shop_id, existing_movement.batch_id,
      existing_movement.movement_type, existing_movement.quantity_delta,
      existing_movement.occurred_at, existing_movement.created_at,
      existing_movement.idempotency_key, true;
    return;
  end if;

  insert into public.batches (
    shop_id,
    product_id,
    expiry_date,
    lot_number,
    current_quantity,
    created_by
  )
  values (
    target_shop_id,
    target_product_id,
    target_expiry_date,
    normalized_lot_number,
    received_quantity,
    caller_id
  )
  returning * into created_batch;

  insert into public.inventory_movements (
    shop_id,
    batch_id,
    movement_type,
    quantity_delta,
    occurred_at,
    created_by,
    idempotency_key
  )
  values (
    target_shop_id,
    created_batch.id,
    'received',
    received_quantity,
    created_batch.created_at,
    caller_id,
    normalized_idempotency_key
  )
  returning * into created_movement;

  return query
  select created_batch.id, created_batch.shop_id, created_batch.product_id,
    created_batch.expiry_date, created_batch.lot_number,
    created_batch.current_quantity, created_batch.created_at,
    created_batch.updated_at, created_movement.id, created_movement.shop_id,
    created_movement.batch_id, created_movement.movement_type,
    created_movement.quantity_delta, created_movement.occurred_at,
    created_movement.created_at, created_movement.idempotency_key, false;
end;
$$;

revoke all on function public.receive_product_stock(uuid, uuid, integer, date, text, text)
  from public, anon, authenticated;
grant execute on function public.receive_product_stock(uuid, uuid, integer, date, text, text)
  to authenticated;
