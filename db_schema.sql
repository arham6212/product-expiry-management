


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."can_manage_public_storefront"("target_shop_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = target_shop_id
        and membership.user_id = auth.uid()
        and membership.role in ('owner', 'manager')
    );
$$;


ALTER FUNCTION "public"."can_manage_public_storefront"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_manual_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "shop_id" "uuid", "name" "text", "brand" "text", "image_url" "text", "source" "text", "source_reference" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "was_created" boolean)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  saved_product record;
  manual_product public.products;
begin
  select external_product.*
  into saved_product
  from public.create_product_for_barcode(
    target_shop_id,
    normalized_barcode,
    barcode_format,
    product_name,
    product_brand,
    null,
    null
  ) as external_product;

  if not saved_product.was_created then
    return query
    select saved_product.id, saved_product.shop_id, saved_product.name,
      saved_product.brand, saved_product.image_url, saved_product.source,
      saved_product.source_reference, saved_product.created_at,
      saved_product.updated_at, false;
    return;
  end if;

  update public.products as product
  set source = 'local_manual',
      source_reference = null
  where product.shop_id = target_shop_id
    and product.id = saved_product.id
  returning product.* into manual_product;

  if not found then
    raise exception using errcode = 'P0002', message = 'Saved Product could not be read.';
  end if;

  return query
  select manual_product.id, manual_product.shop_id, manual_product.name,
    manual_product.brand, manual_product.image_url, manual_product.source,
    manual_product.source_reference, manual_product.created_at,
    manual_product.updated_at, true;
end;
$$;


ALTER FUNCTION "public"."create_manual_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text" DEFAULT NULL::"text", "product_image_url" "text" DEFAULT NULL::"text", "product_source_reference" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "shop_id" "uuid", "name" "text", "brand" "text", "image_url" "text", "source" "text", "source_reference" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "was_created" boolean)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
declare
  normalized_name text := regexp_replace(btrim(product_name), '\s+', ' ', 'g');
  normalized_brand text := nullif(regexp_replace(btrim(product_brand), '\s+', ' ', 'g'), '');
  existing_product public.products;
  created_product public.products;
begin
  if not public.is_shop_member(target_shop_id) then
    raise exception using errcode = '42501', message = 'Shop membership is required.';
  end if;
  if normalized_barcode !~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$' then
    raise exception using errcode = '22023', message = 'Barcode format is not supported.';
  end if;
  if barcode_format not in ('ean8', 'upc_a', 'ean13', 'gtin14', 'unknown') then
    raise exception using errcode = '22023', message = 'Barcode symbology is not supported.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 1 and 240 then
    raise exception using errcode = '22023', message = 'Product name must be 1 to 240 characters.';
  end if;
  if product_image_url is not null and product_image_url !~ '^https?://' then
    raise exception using errcode = '22023', message = 'Product image URL must use HTTP or HTTPS.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_shop_id::text || ':' || normalized_barcode, 0)
  );

  select product.*
  into existing_product
  from public.product_barcodes mapping
  join public.products product
    on product.shop_id = mapping.shop_id
   and product.id = mapping.product_id
  where mapping.shop_id = target_shop_id
    and mapping.barcode = normalized_barcode;

  if found then
    return query
    select existing_product.id, existing_product.shop_id, existing_product.name,
      existing_product.brand, existing_product.image_url, existing_product.source,
      existing_product.source_reference, existing_product.created_at,
      existing_product.updated_at, false;
    return;
  end if;

  insert into public.products (
    shop_id,
    name,
    brand,
    image_url,
    source,
    source_reference
  )
  values (
    target_shop_id,
    normalized_name,
    normalized_brand,
    product_image_url,
    'open_food_facts',
    nullif(btrim(product_source_reference), '')
  )
  returning * into created_product;

  insert into public.product_barcodes (
    shop_id,
    product_id,
    barcode,
    format,
    is_primary
  )
  values (
    target_shop_id,
    created_product.id,
    normalized_barcode,
    barcode_format,
    true
  );

  return query
  select created_product.id, created_product.shop_id, created_product.name,
    created_product.brand, created_product.image_url, created_product.source,
    created_product.source_reference, created_product.created_at,
    created_product.updated_at, true;
end;
$_$;


ALTER FUNCTION "public"."create_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text", "product_image_url" "text", "product_source_reference" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."shops" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "time_zone" "text" DEFAULT 'UTC'::"text" NOT NULL,
    "currency_code" "text" DEFAULT 'USD'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "shops_currency_code_check" CHECK (("currency_code" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "shops_name_check" CHECK ((("char_length"("btrim"("name")) >= 1) AND ("char_length"("btrim"("name")) <= 120))),
    CONSTRAINT "shops_time_zone_check" CHECK (("char_length"("btrim"("time_zone")) > 0))
);


ALTER TABLE "public"."shops" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_shop_with_owner"("shop_name" "text") RETURNS "public"."shops"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_shop_with_owner"("shop_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_public_shop_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.public_shop_profiles (shop_id, display_name)
  values (new.id, new.name)
  on conflict (shop_id) do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_public_shop_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invite_code"() RETURNS "text"
    LANGUAGE "sql"
    AS $$
  select upper(substring(md5(random()::text) from 1 for 6));
$$;


ALTER FUNCTION "public"."generate_invite_code"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_invites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval) NOT NULL,
    CONSTRAINT "shop_invites_code_check" CHECK (("char_length"("btrim"("code")) >= 6)),
    CONSTRAINT "shop_invites_expiry_after_creation_check" CHECK (("expires_at" > "created_at"))
);


ALTER TABLE "public"."shop_invites" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_active_shop_invite"("target_shop_id" "uuid") RETURNS SETOF "public"."shop_invites"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."get_active_shop_invite"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_expiry_dashboard"("target_shop_id" "uuid") RETURNS TABLE("reference_date" "date", "shop_id" "uuid", "batch_id" "uuid", "product_id" "uuid", "product_name" "text", "product_brand" "text", "expiry_date" "date", "days_to_expiry" integer, "current_quantity" integer, "lot_number" "text", "received_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_expiry_dashboard"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_shop_members_with_users"("target_shop_id" "uuid") RETURNS TABLE("user_id" "uuid", "email" "text", "role" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.shop_memberships AS m
    WHERE m.shop_id = target_shop_id
      AND m.user_id = auth.uid()
      AND m.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT m.user_id, u.email::text, m.role, m.created_at
  FROM public.shop_memberships AS m
  JOIN auth.users AS u ON u.id = m.user_id
  WHERE m.shop_id = target_shop_id
  ORDER BY m.created_at;
END;
$$;


ALTER FUNCTION "public"."get_shop_members_with_users"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_shop_pending_requests_with_users"("target_shop_id" "uuid") RETURNS TABLE("request_id" "uuid", "user_id" "uuid", "email" "text", "status" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.shop_memberships AS m
    WHERE m.shop_id = target_shop_id
      AND m.user_id = auth.uid()
      AND m.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT r.id, r.user_id, u.email::text, r.status, r.created_at
  FROM public.shop_join_requests AS r
  JOIN auth.users AS u ON u.id = r.user_id
  WHERE r.shop_id = target_shop_id
    AND r.status = 'pending'
  ORDER BY r.created_at;
END;
$$;


ALTER FUNCTION "public"."get_shop_pending_requests_with_users"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_shop_member"("target_shop_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.shop_memberships membership
      where membership.shop_id = target_shop_id
        and membership.user_id = (select auth.uid())
    );
$$;


ALTER FUNCTION "public"."is_shop_member"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."receive_product_stock"("target_shop_id" "uuid", "target_product_id" "uuid", "received_quantity" integer, "target_expiry_date" "date", "target_lot_number" "text", "request_idempotency_key" "text") RETURNS TABLE("batch_id" "uuid", "batch_shop_id" "uuid", "batch_product_id" "uuid", "batch_expiry_date" "date", "batch_lot_number" "text", "batch_current_quantity" integer, "batch_created_at" timestamp with time zone, "batch_updated_at" timestamp with time zone, "movement_id" "uuid", "movement_shop_id" "uuid", "movement_batch_id" "uuid", "movement_type" "text", "movement_quantity_delta" integer, "movement_occurred_at" timestamp with time zone, "movement_created_at" timestamp with time zone, "movement_idempotency_key" "text", "was_duplicate" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
  if target_expiry_date is null then
    raise exception using errcode = '22023', message = 'Expiry date is required.';
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


ALTER FUNCTION "public"."receive_product_stock"("target_shop_id" "uuid", "target_product_id" "uuid", "received_quantity" integer, "target_expiry_date" "date", "target_lot_number" "text", "request_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_to_join_shop"("join_code" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."request_to_join_shop"("join_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_join_request"("request_id" "uuid", "new_status" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."review_join_request"("request_id" "uuid", "new_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rotate_shop_invite_code"("target_shop_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."rotate_shop_invite_code"("target_shop_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_shop_invite_status"("target_shop_id" "uuid", "target_is_active" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."update_shop_invite_status"("target_shop_id" "uuid", "target_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_shop_member_role"("target_shop_id" "uuid", "target_user_id" "uuid", "requested_role" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."update_shop_member_role"("target_shop_id" "uuid", "target_user_id" "uuid", "requested_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_deal"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  listing_price integer;
begin
  if not public.can_manage_public_storefront(new.shop_id) then
    raise exception using
      errcode = '42501',
      message = 'Only an owner or manager can manage deals.';
  end if;

  if tg_op = 'UPDATE'
    and (new.shop_id, new.listing_id) is distinct from (old.shop_id, old.listing_id) then
    raise exception using
      errcode = '22023',
      message = 'A deal cannot be moved to another listing.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.shop_id::text || ':' || new.listing_id::text, 0)
  );

  select listing.price_minor
  into listing_price
  from public.published_product_listings as listing
  where listing.shop_id = new.shop_id
    and listing.id = new.listing_id;

  if listing_price is null then
    raise exception using errcode = '23503', message = 'Deal listing is unavailable.';
  end if;
  if new.offer_price_minor >= listing_price then
    raise exception using
      errcode = '22023',
      message = 'Offer price must be lower than the listing price.';
  end if;

  if new.is_enabled and exists (
    select 1
    from public.deals as existing
    where existing.shop_id = new.shop_id
      and existing.listing_id = new.listing_id
      and existing.id is distinct from new.id
      and existing.is_enabled
      and existing.starts_at < new.ends_at
      and existing.ends_at > new.starts_at
  ) then
    raise exception using
      errcode = '23P01',
      message = 'Enabled deal windows cannot overlap for one listing.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."validate_deal"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_listing_price_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.shop_id::text || ':' || new.id::text, 0)
  );

  if new.price_minor <> old.price_minor and exists (
    select 1
    from public.deals as deal
    where deal.shop_id = new.shop_id
      and deal.listing_id = new.id
      and deal.is_enabled
      and deal.offer_price_minor >= new.price_minor
  ) then
    raise exception using
      errcode = '22023',
      message = 'Listing price must remain above every enabled offer price.';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."validate_listing_price_change"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "expiry_date" "date",
    "lot_number" "text",
    "current_quantity" integer NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "batches_current_quantity_check" CHECK ((("current_quantity" >= 0) AND ("current_quantity" <= 2147483647))),
    CONSTRAINT "batches_lot_number_check" CHECK ((("lot_number" IS NULL) OR (("char_length"("btrim"("lot_number")) >= 1) AND ("char_length"("btrim"("lot_number")) <= 120))))
);


ALTER TABLE "public"."batches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."catalog_product_barcodes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "catalog_product_id" "uuid" NOT NULL,
    "barcode" "text" NOT NULL,
    "format" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "catalog_product_barcodes_barcode_check" CHECK (("barcode" ~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$'::"text")),
    CONSTRAINT "catalog_product_barcodes_format_check" CHECK (("format" = ANY (ARRAY['ean8'::"text", 'upc_a'::"text", 'ean13'::"text", 'gtin14'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."catalog_product_barcodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."catalog_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "canonical_name" "text" NOT NULL,
    "brand" "text",
    "image_url" "text",
    "source" "text" NOT NULL,
    "source_reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "catalog_products_brand_check" CHECK ((("brand" IS NULL) OR (("char_length"("btrim"("brand")) >= 1) AND ("char_length"("btrim"("brand")) <= 240)))),
    CONSTRAINT "catalog_products_canonical_name_check" CHECK ((("char_length"("btrim"("canonical_name")) >= 1) AND ("char_length"("btrim"("canonical_name")) <= 240))),
    CONSTRAINT "catalog_products_image_url_check" CHECK ((("image_url" IS NULL) OR ("image_url" ~ '^https?://'::"text"))),
    CONSTRAINT "catalog_products_source_check" CHECK (("source" = ANY (ARRAY['open_food_facts'::"text", 'verified_manual'::"text"])))
);


ALTER TABLE "public"."catalog_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "listing_id" "uuid" NOT NULL,
    "offer_price_minor" integer NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "title" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "deals_description_check" CHECK ((("description" IS NULL) OR (("char_length"("btrim"("description")) >= 1) AND ("char_length"("btrim"("description")) <= 1000)))),
    CONSTRAINT "deals_offer_price_minor_check" CHECK ((("offer_price_minor" >= 1) AND ("offer_price_minor" <= 2147483647))),
    CONSTRAINT "deals_time_window_check" CHECK (("starts_at" < "ends_at")),
    CONSTRAINT "deals_title_check" CHECK ((("title" IS NULL) OR (("char_length"("btrim"("title")) >= 1) AND ("char_length"("btrim"("title")) <= 160))))
);


ALTER TABLE "public"."deals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "batch_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "quantity_delta" integer NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "idempotency_key" "text" NOT NULL,
    CONSTRAINT "inventory_movements_idempotency_key_check" CHECK ((("char_length"("btrim"("idempotency_key")) >= 1) AND ("char_length"("btrim"("idempotency_key")) <= 200))),
    CONSTRAINT "inventory_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['received'::"text", 'sold'::"text", 'disposed'::"text", 'returned'::"text", 'adjusted'::"text"]))),
    CONSTRAINT "inventory_movements_quantity_direction" CHECK (((("movement_type" = 'received'::"text") AND ("quantity_delta" > 0)) OR (("movement_type" = ANY (ARRAY['sold'::"text", 'disposed'::"text", 'returned'::"text"])) AND ("quantity_delta" < 0)) OR (("movement_type" = 'adjusted'::"text") AND ("quantity_delta" <> 0))))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_barcodes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "barcode" "text" NOT NULL,
    "format" "text" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_barcodes_barcode_check" CHECK (("barcode" ~ '^[0-9]{8}$|^[0-9]{12}$|^[0-9]{13}$|^[0-9]{14}$'::"text")),
    CONSTRAINT "product_barcodes_format_check" CHECK (("format" = ANY (ARRAY['ean8'::"text", 'upc_a'::"text", 'ean13'::"text", 'gtin14'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."product_barcodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "brand" "text",
    "image_url" "text",
    "source" "text" NOT NULL,
    "source_reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "catalog_product_id" "uuid",
    CONSTRAINT "products_brand_check" CHECK ((("brand" IS NULL) OR (("char_length"("btrim"("brand")) >= 1) AND ("char_length"("btrim"("brand")) <= 240)))),
    CONSTRAINT "products_image_url_check" CHECK ((("image_url" IS NULL) OR ("image_url" ~ '^https?://'::"text"))),
    CONSTRAINT "products_name_check" CHECK ((("char_length"("btrim"("name")) >= 1) AND ("char_length"("btrim"("name")) <= 240))),
    CONSTRAINT "products_source_check" CHECK (("source" = ANY (ARRAY['local_manual'::"text", 'open_food_facts'::"text"])))
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."public_shop_profiles" (
    "shop_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "description" "text",
    "logo_url" "text",
    "area" "text",
    "is_enabled" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "public_shop_profiles_area_check" CHECK ((("area" IS NULL) OR (("char_length"("btrim"("area")) >= 1) AND ("char_length"("btrim"("area")) <= 160)))),
    CONSTRAINT "public_shop_profiles_description_check" CHECK ((("description" IS NULL) OR (("char_length"("btrim"("description")) >= 1) AND ("char_length"("btrim"("description")) <= 1000)))),
    CONSTRAINT "public_shop_profiles_display_name_check" CHECK ((("char_length"("btrim"("display_name")) >= 1) AND ("char_length"("btrim"("display_name")) <= 120))),
    CONSTRAINT "public_shop_profiles_logo_url_check" CHECK ((("logo_url" IS NULL) OR ("logo_url" ~ '^https?://'::"text")))
);


ALTER TABLE "public"."public_shop_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."published_product_listings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "display_name" "text" NOT NULL,
    "description" "text",
    "image_url" "text",
    "price_minor" integer NOT NULL,
    "currency_code" "text" NOT NULL,
    "is_published" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "published_product_listings_currency_code_check" CHECK (("currency_code" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "published_product_listings_description_check" CHECK ((("description" IS NULL) OR (("char_length"("btrim"("description")) >= 1) AND ("char_length"("btrim"("description")) <= 2000)))),
    CONSTRAINT "published_product_listings_display_name_check" CHECK ((("char_length"("btrim"("display_name")) >= 1) AND ("char_length"("btrim"("display_name")) <= 240))),
    CONSTRAINT "published_product_listings_image_url_check" CHECK ((("image_url" IS NULL) OR ("image_url" ~ '^https?://'::"text"))),
    CONSTRAINT "published_product_listings_price_minor_check" CHECK ((("price_minor" >= 1) AND ("price_minor" <= 2147483647)))
);


ALTER TABLE "public"."published_product_listings" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_storefront_deals" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "id",
    "shop_id",
    "listing_id",
    "offer_price_minor",
    "starts_at",
    "ends_at",
    "is_enabled",
    "title",
    "description",
    "created_at",
    "updated_at"
   FROM "public"."deals" "deal"
  WHERE ("is_enabled" AND ("starts_at" <= "now"()) AND ("ends_at" > "now"()) AND (EXISTS ( SELECT 1
           FROM ("public"."published_product_listings" "listing"
             JOIN "public"."public_shop_profiles" "profile" ON (("profile"."shop_id" = "listing"."shop_id")))
          WHERE (("listing"."shop_id" = "deal"."shop_id") AND ("listing"."id" = "deal"."listing_id") AND "listing"."is_published" AND "profile"."is_enabled"))));


ALTER VIEW "public"."public_storefront_deals" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_storefront_listings" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "id",
    "shop_id",
    "display_name",
    "description",
    "image_url",
    "price_minor",
    "currency_code",
    "is_published",
    "created_at",
    "updated_at"
   FROM "public"."published_product_listings" "listing"
  WHERE ("is_published" AND (EXISTS ( SELECT 1
           FROM "public"."public_shop_profiles" "profile"
          WHERE (("profile"."shop_id" = "listing"."shop_id") AND "profile"."is_enabled"))));


ALTER VIEW "public"."public_storefront_listings" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."public_storefront_shops" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "shop_id",
    "display_name",
    "description",
    "logo_url",
    "area",
    "is_enabled",
    "created_at",
    "updated_at"
   FROM "public"."public_shop_profiles" "profile"
  WHERE "is_enabled";


ALTER VIEW "public"."public_storefront_shops" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_join_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shop_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "uuid",
    CONSTRAINT "shop_join_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."shop_join_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_memberships" (
    "shop_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "shop_memberships_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'manager'::"text", 'worker'::"text"])))
);


ALTER TABLE "public"."shop_memberships" OWNER TO "postgres";


ALTER TABLE ONLY "public"."batches"
    ADD CONSTRAINT "batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."batches"
    ADD CONSTRAINT "batches_shop_id_id_key" UNIQUE ("shop_id", "id");



ALTER TABLE ONLY "public"."catalog_product_barcodes"
    ADD CONSTRAINT "catalog_product_barcodes_barcode_key" UNIQUE ("barcode");



ALTER TABLE ONLY "public"."catalog_product_barcodes"
    ADD CONSTRAINT "catalog_product_barcodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."catalog_products"
    ADD CONSTRAINT "catalog_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_shop_id_id_key" UNIQUE ("shop_id", "id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_shop_idempotency_key" UNIQUE ("shop_id", "idempotency_key");



ALTER TABLE ONLY "public"."product_barcodes"
    ADD CONSTRAINT "product_barcodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_barcodes"
    ADD CONSTRAINT "product_barcodes_shop_barcode_key" UNIQUE ("shop_id", "barcode");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_shop_id_id_key" UNIQUE ("shop_id", "id");



ALTER TABLE ONLY "public"."public_shop_profiles"
    ADD CONSTRAINT "public_shop_profiles_pkey" PRIMARY KEY ("shop_id");



ALTER TABLE ONLY "public"."published_product_listings"
    ADD CONSTRAINT "published_product_listings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."published_product_listings"
    ADD CONSTRAINT "published_product_listings_shop_id_id_key" UNIQUE ("shop_id", "id");



ALTER TABLE ONLY "public"."published_product_listings"
    ADD CONSTRAINT "published_product_listings_shop_product_key" UNIQUE ("shop_id", "product_id");



ALTER TABLE ONLY "public"."shop_invites"
    ADD CONSTRAINT "shop_invites_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."shop_invites"
    ADD CONSTRAINT "shop_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_join_requests"
    ADD CONSTRAINT "shop_join_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_memberships"
    ADD CONSTRAINT "shop_memberships_pkey" PRIMARY KEY ("shop_id", "user_id");



ALTER TABLE ONLY "public"."shop_memberships"
    ADD CONSTRAINT "shop_memberships_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."shops"
    ADD CONSTRAINT "shops_pkey" PRIMARY KEY ("id");



CREATE INDEX "batches_shop_expiry_idx" ON "public"."batches" USING "btree" ("shop_id", "expiry_date");



CREATE INDEX "batches_shop_product_idx" ON "public"."batches" USING "btree" ("shop_id", "product_id");



CREATE UNIQUE INDEX "catalog_products_source_reference_key" ON "public"."catalog_products" USING "btree" ("source", "source_reference") WHERE ("source_reference" IS NOT NULL);



CREATE INDEX "deals_listing_window_idx" ON "public"."deals" USING "btree" ("shop_id", "listing_id", "starts_at", "ends_at") WHERE "is_enabled";



CREATE INDEX "inventory_movements_shop_batch_idx" ON "public"."inventory_movements" USING "btree" ("shop_id", "batch_id");



CREATE INDEX "inventory_movements_shop_occurred_idx" ON "public"."inventory_movements" USING "btree" ("shop_id", "occurred_at" DESC);



CREATE INDEX "product_barcodes_product_id_idx" ON "public"."product_barcodes" USING "btree" ("product_id");



CREATE INDEX "products_catalog_product_id_idx" ON "public"."products" USING "btree" ("catalog_product_id") WHERE ("catalog_product_id" IS NOT NULL);



CREATE INDEX "products_shop_id_idx" ON "public"."products" USING "btree" ("shop_id");



CREATE INDEX "published_product_listings_public_idx" ON "public"."published_product_listings" USING "btree" ("shop_id", "display_name") WHERE "is_published";



CREATE UNIQUE INDEX "shop_invites_one_active_per_shop_idx" ON "public"."shop_invites" USING "btree" ("shop_id") WHERE "is_active";



CREATE INDEX "shop_invites_shop_id_idx" ON "public"."shop_invites" USING "btree" ("shop_id");



CREATE INDEX "shop_join_requests_shop_id_idx" ON "public"."shop_join_requests" USING "btree" ("shop_id");



CREATE INDEX "shop_join_requests_user_id_idx" ON "public"."shop_join_requests" USING "btree" ("user_id");



CREATE UNIQUE INDEX "shop_join_requests_user_pending_idx" ON "public"."shop_join_requests" USING "btree" ("user_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "shop_memberships_user_id_idx" ON "public"."shop_memberships" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "batches_set_updated_at" BEFORE UPDATE ON "public"."batches" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "catalog_products_set_updated_at" BEFORE UPDATE ON "public"."catalog_products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "deals_set_updated_at" BEFORE UPDATE ON "public"."deals" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "deals_validate" BEFORE INSERT OR UPDATE ON "public"."deals" FOR EACH ROW EXECUTE FUNCTION "public"."validate_deal"();



CREATE OR REPLACE TRIGGER "products_set_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "public_shop_profiles_set_updated_at" BEFORE UPDATE ON "public"."public_shop_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "published_product_listings_set_updated_at" BEFORE UPDATE ON "public"."published_product_listings" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "published_product_listings_validate_price" BEFORE UPDATE OF "price_minor" ON "public"."published_product_listings" FOR EACH ROW EXECUTE FUNCTION "public"."validate_listing_price_change"();



CREATE OR REPLACE TRIGGER "shops_ensure_public_profile" AFTER INSERT ON "public"."shops" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_public_shop_profile"();



CREATE OR REPLACE TRIGGER "shops_set_updated_at" BEFORE UPDATE ON "public"."shops" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."batches"
    ADD CONSTRAINT "batches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."batches"
    ADD CONSTRAINT "batches_product_shop_fkey" FOREIGN KEY ("shop_id", "product_id") REFERENCES "public"."products"("shop_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."catalog_product_barcodes"
    ADD CONSTRAINT "catalog_product_barcodes_catalog_product_id_fkey" FOREIGN KEY ("catalog_product_id") REFERENCES "public"."catalog_products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_listing_shop_fkey" FOREIGN KEY ("shop_id", "listing_id") REFERENCES "public"."published_product_listings"("shop_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_batch_shop_fkey" FOREIGN KEY ("shop_id", "batch_id") REFERENCES "public"."batches"("shop_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."product_barcodes"
    ADD CONSTRAINT "product_barcodes_product_shop_fkey" FOREIGN KEY ("shop_id", "product_id") REFERENCES "public"."products"("shop_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_catalog_product_id_fkey" FOREIGN KEY ("catalog_product_id") REFERENCES "public"."catalog_products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."public_shop_profiles"
    ADD CONSTRAINT "public_shop_profiles_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."published_product_listings"
    ADD CONSTRAINT "published_product_listings_product_shop_fkey" FOREIGN KEY ("shop_id", "product_id") REFERENCES "public"."products"("shop_id", "id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."published_product_listings"
    ADD CONSTRAINT "published_product_listings_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."public_shop_profiles"("shop_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_invites"
    ADD CONSTRAINT "shop_invites_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_invites"
    ADD CONSTRAINT "shop_invites_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_join_requests"
    ADD CONSTRAINT "shop_join_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shop_join_requests"
    ADD CONSTRAINT "shop_join_requests_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_join_requests"
    ADD CONSTRAINT "shop_join_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_memberships"
    ADD CONSTRAINT "shop_memberships_shop_id_fkey" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_memberships"
    ADD CONSTRAINT "shop_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Managers can insert their shop deals" ON "public"."deals" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."can_manage_public_storefront"("deals"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can insert their shop listings" ON "public"."published_product_listings" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."can_manage_public_storefront"("published_product_listings"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can insert their shop profile" ON "public"."public_shop_profiles" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."can_manage_public_storefront"("public_shop_profiles"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can read their shop deals" ON "public"."deals" FOR SELECT TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("deals"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can read their shop listings" ON "public"."published_product_listings" FOR SELECT TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("published_product_listings"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can read their shop profile" ON "public"."public_shop_profiles" FOR SELECT TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("public_shop_profiles"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can update their shop deals" ON "public"."deals" FOR UPDATE TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("deals"."shop_id") AS "can_manage_public_storefront")) WITH CHECK (( SELECT "public"."can_manage_public_storefront"("deals"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can update their shop listings" ON "public"."published_product_listings" FOR UPDATE TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("published_product_listings"."shop_id") AS "can_manage_public_storefront")) WITH CHECK (( SELECT "public"."can_manage_public_storefront"("published_product_listings"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Managers can update their shop profile" ON "public"."public_shop_profiles" FOR UPDATE TO "authenticated" USING (( SELECT "public"."can_manage_public_storefront"("public_shop_profiles"."shop_id") AS "can_manage_public_storefront")) WITH CHECK (( SELECT "public"."can_manage_public_storefront"("public_shop_profiles"."shop_id") AS "can_manage_public_storefront"));



CREATE POLICY "Members can insert product barcodes" ON "public"."product_barcodes" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."is_shop_member"("product_barcodes"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can insert products" ON "public"."products" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "public"."is_shop_member"("products"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can read batches" ON "public"."batches" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_shop_member"("batches"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can read inventory movements" ON "public"."inventory_movements" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_shop_member"("inventory_movements"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can read product barcodes" ON "public"."product_barcodes" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_shop_member"("product_barcodes"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can read products" ON "public"."products" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_shop_member"("products"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can read their shops" ON "public"."shops" FOR SELECT TO "authenticated" USING (( SELECT "public"."is_shop_member"("shops"."id") AS "is_shop_member"));



CREATE POLICY "Members can update product barcodes" ON "public"."product_barcodes" FOR UPDATE TO "authenticated" USING (( SELECT "public"."is_shop_member"("product_barcodes"."shop_id") AS "is_shop_member")) WITH CHECK (( SELECT "public"."is_shop_member"("product_barcodes"."shop_id") AS "is_shop_member"));



CREATE POLICY "Members can update products" ON "public"."products" FOR UPDATE TO "authenticated" USING (( SELECT "public"."is_shop_member"("products"."shop_id") AS "is_shop_member")) WITH CHECK (( SELECT "public"."is_shop_member"("products"."shop_id") AS "is_shop_member"));



CREATE POLICY "Owners can read requests for their shop" ON "public"."shop_join_requests" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shop_memberships" "m"
  WHERE (("m"."shop_id" = "shop_join_requests"."shop_id") AND ("m"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("m"."role" = 'owner'::"text")))));



CREATE POLICY "Owners can read shop invites" ON "public"."shop_invites" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shop_memberships" "m"
  WHERE (("m"."shop_id" = "shop_invites"."shop_id") AND ("m"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("m"."role" = 'owner'::"text")))));



CREATE POLICY "Owners can update their shops" ON "public"."shops" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shop_memberships" "membership"
  WHERE (("membership"."shop_id" = "shops"."id") AND ("membership"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("membership"."role" = 'owner'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."shop_memberships" "membership"
  WHERE (("membership"."shop_id" = "shops"."id") AND ("membership"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("membership"."role" = 'owner'::"text")))));



CREATE POLICY "Public can read active deals" ON "public"."deals" FOR SELECT TO "authenticated", "anon" USING (("is_enabled" AND ("starts_at" <= "now"()) AND ("ends_at" > "now"()) AND (EXISTS ( SELECT 1
   FROM ("public"."published_product_listings" "listing"
     JOIN "public"."public_shop_profiles" "profile" ON (("profile"."shop_id" = "listing"."shop_id")))
  WHERE (("listing"."shop_id" = "deals"."shop_id") AND ("listing"."id" = "deals"."listing_id") AND "listing"."is_published" AND "profile"."is_enabled")))));



CREATE POLICY "Public can read enabled shop profiles" ON "public"."public_shop_profiles" FOR SELECT TO "authenticated", "anon" USING ("is_enabled");



CREATE POLICY "Public can read published listings" ON "public"."published_product_listings" FOR SELECT TO "authenticated", "anon" USING (("is_published" AND (EXISTS ( SELECT 1
   FROM "public"."public_shop_profiles" "profile"
  WHERE (("profile"."shop_id" = "published_product_listings"."shop_id") AND "profile"."is_enabled")))));



CREATE POLICY "Users can read their memberships" ON "public"."shop_memberships" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can read their own requests" ON "public"."shop_join_requests" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."batches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."catalog_product_barcodes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."catalog_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_barcodes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."public_shop_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."published_product_listings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_join_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_memberships" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shops" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































REVOKE ALL ON FUNCTION "public"."can_manage_public_storefront"("target_shop_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_manage_public_storefront"("target_shop_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."can_manage_public_storefront"("target_shop_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_manual_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_manual_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_manual_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text", "product_image_url" "text", "product_source_reference" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text", "product_image_url" "text", "product_source_reference" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_product_for_barcode"("target_shop_id" "uuid", "normalized_barcode" "text", "barcode_format" "text", "product_name" "text", "product_brand" "text", "product_image_url" "text", "product_source_reference" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."shops" TO "service_role";
GRANT SELECT,UPDATE ON TABLE "public"."shops" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_shop_with_owner"("shop_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_shop_with_owner"("shop_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_shop_with_owner"("shop_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ensure_public_shop_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_public_shop_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."generate_invite_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "service_role";



GRANT ALL ON TABLE "public"."shop_invites" TO "service_role";
GRANT SELECT ON TABLE "public"."shop_invites" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_active_shop_invite"("target_shop_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_active_shop_invite"("target_shop_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_active_shop_invite"("target_shop_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_expiry_dashboard"("target_shop_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_expiry_dashboard"("target_shop_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_expiry_dashboard"("target_shop_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "public"."get_shop_members_with_users"("target_shop_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_shop_members_with_users"("target_shop_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_shop_members_with_users"("target_shop_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_shop_pending_requests_with_users"("target_shop_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_shop_pending_requests_with_users"("target_shop_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_shop_pending_requests_with_users"("target_shop_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_shop_member"("target_shop_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_shop_member"("target_shop_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."is_shop_member"("target_shop_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."receive_product_stock"("target_shop_id" "uuid", "target_product_id" "uuid", "received_quantity" integer, "target_expiry_date" "date", "target_lot_number" "text", "request_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."receive_product_stock"("target_shop_id" "uuid", "target_product_id" "uuid", "received_quantity" integer, "target_expiry_date" "date", "target_lot_number" "text", "request_idempotency_key" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."receive_product_stock"("target_shop_id" "uuid", "target_product_id" "uuid", "received_quantity" integer, "target_expiry_date" "date", "target_lot_number" "text", "request_idempotency_key" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."request_to_join_shop"("join_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_to_join_shop"("join_code" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."request_to_join_shop"("join_code" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."review_join_request"("request_id" "uuid", "new_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_join_request"("request_id" "uuid", "new_status" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."review_join_request"("request_id" "uuid", "new_status" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rotate_shop_invite_code"("target_shop_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rotate_shop_invite_code"("target_shop_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."rotate_shop_invite_code"("target_shop_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_shop_invite_status"("target_shop_id" "uuid", "target_is_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_shop_invite_status"("target_shop_id" "uuid", "target_is_active" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_shop_invite_status"("target_shop_id" "uuid", "target_is_active" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_shop_member_role"("target_shop_id" "uuid", "target_user_id" "uuid", "requested_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_shop_member_role"("target_shop_id" "uuid", "target_user_id" "uuid", "requested_role" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_shop_member_role"("target_shop_id" "uuid", "target_user_id" "uuid", "requested_role" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."validate_deal"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_deal"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_listing_price_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_listing_price_change"() TO "service_role";


















GRANT ALL ON TABLE "public"."batches" TO "service_role";
GRANT SELECT ON TABLE "public"."batches" TO "authenticated";



GRANT ALL ON TABLE "public"."catalog_product_barcodes" TO "service_role";



GRANT ALL ON TABLE "public"."catalog_products" TO "service_role";



GRANT ALL ON TABLE "public"."deals" TO "service_role";
GRANT SELECT ON TABLE "public"."deals" TO "anon";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."deals" TO "authenticated";



GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";
GRANT SELECT ON TABLE "public"."inventory_movements" TO "authenticated";



GRANT ALL ON TABLE "public"."product_barcodes" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."product_barcodes" TO "authenticated";



GRANT ALL ON TABLE "public"."products" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."products" TO "authenticated";



GRANT ALL ON TABLE "public"."public_shop_profiles" TO "service_role";
GRANT SELECT ON TABLE "public"."public_shop_profiles" TO "anon";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."public_shop_profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."published_product_listings" TO "service_role";
GRANT SELECT ON TABLE "public"."published_product_listings" TO "anon";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."published_product_listings" TO "authenticated";



GRANT ALL ON TABLE "public"."public_storefront_deals" TO "service_role";
GRANT SELECT ON TABLE "public"."public_storefront_deals" TO "anon";
GRANT SELECT ON TABLE "public"."public_storefront_deals" TO "authenticated";



GRANT ALL ON TABLE "public"."public_storefront_listings" TO "service_role";
GRANT SELECT ON TABLE "public"."public_storefront_listings" TO "anon";
GRANT SELECT ON TABLE "public"."public_storefront_listings" TO "authenticated";



GRANT ALL ON TABLE "public"."public_storefront_shops" TO "service_role";
GRANT SELECT ON TABLE "public"."public_storefront_shops" TO "anon";
GRANT SELECT ON TABLE "public"."public_storefront_shops" TO "authenticated";



GRANT ALL ON TABLE "public"."shop_join_requests" TO "service_role";
GRANT SELECT ON TABLE "public"."shop_join_requests" TO "authenticated";



GRANT ALL ON TABLE "public"."shop_memberships" TO "service_role";
GRANT SELECT ON TABLE "public"."shop_memberships" TO "authenticated";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































