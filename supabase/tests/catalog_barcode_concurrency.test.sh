#!/bin/sh
set -eu

db_container="supabase_db_product_expiry_management"
same_shop="d0000000-0000-0000-0000-000000000001"
same_user="d0000000-0000-0000-0000-000000000011"
same_barcode="6291000000008"
cross_barcode="6291000000015"
result_dir="$(mktemp -d)"

cleanup_results() {
  docker exec -i "$db_container" psql -X -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -Atqc \
    "delete from public.shops where id::text like 'd0000000-0000-0000-0000-%';
     delete from auth.users where id::text like 'd0000000-0000-0000-0000-%';
     delete from public.catalog_products
     where id not in (
       select catalog_product_id from public.products where catalog_product_id is not null
     ) and canonical_name = 'Concurrent product';" >/dev/null
  find "$result_dir" -type f -delete
  rmdir "$result_dir"
}
trap cleanup_results EXIT

query() {
  docker exec -i "$db_container" psql -X -U postgres -d postgres \
    -v ON_ERROR_STOP=1 -Atqc "$1"
}

call_manual_rpc() {
  shop_id="$1"
  user_id="$2"
  barcode="$3"
  output_file="$4"
  query "begin;
    set local role authenticated;
    select set_config('request.jwt.claim.sub', '$user_id', true);
    select set_config('request.jwt.claim.role', 'authenticated', true);
    select id from public.create_manual_product_for_barcode(
      '$shop_id', '$barcode', 'ean13', 'Concurrent product', 'Concurrency brand'
    );
    commit;" >"$output_file" 2>&1
}

query "delete from public.shops where id::text like 'd0000000-0000-0000-0000-%';
  delete from auth.users where id::text like 'd0000000-0000-0000-0000-%';
  delete from public.catalog_products
  where id not in (select catalog_product_id from public.products where catalog_product_id is not null)
    and canonical_name = 'Concurrent product';
  insert into auth.users (id, email) values
    ('$same_user', 'catalog-concurrency-1@example.test'),
    ('d0000000-0000-0000-0000-000000000012', 'catalog-concurrency-2@example.test'),
    ('d0000000-0000-0000-0000-000000000013', 'catalog-concurrency-3@example.test'),
    ('d0000000-0000-0000-0000-000000000014', 'catalog-concurrency-4@example.test');
  insert into public.shops (id, name) values
    ('$same_shop', 'Concurrency shop 1'),
    ('d0000000-0000-0000-0000-000000000002', 'Concurrency shop 2'),
    ('d0000000-0000-0000-0000-000000000003', 'Concurrency shop 3'),
    ('d0000000-0000-0000-0000-000000000004', 'Concurrency shop 4');
  insert into public.shop_memberships (shop_id, user_id, role) values
    ('$same_shop', '$same_user', 'owner'),
    ('d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000012', 'owner'),
    ('d0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000013', 'owner'),
    ('d0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000014', 'owner');"

same_pids=""
i=1
while [ "$i" -le 8 ]; do
  call_manual_rpc "$same_shop" "$same_user" "$same_barcode" "$result_dir/same-$i" &
  same_pids="$same_pids $!"
  i=$((i + 1))
done
for pid in $same_pids; do
  wait "$pid"
done

same_counts="$(query "select
  (select count(*) from public.catalog_product_barcodes where barcode = '$same_barcode'),
  (select count(*) from public.product_barcodes where shop_id = '$same_shop' and barcode = '$same_barcode'),
  (select count(*) from public.products product join public.product_barcodes mapping on mapping.product_id = product.id where mapping.shop_id = '$same_shop' and mapping.barcode = '$same_barcode');")"
if [ "$same_counts" != "1|1|1" ]; then
  echo "same-shop concurrency failed: $same_counts" >&2
  exit 1
fi

call_manual_rpc "$same_shop" "$same_user" "$cross_barcode" "$result_dir/cross-1" & p1=$!
call_manual_rpc "d0000000-0000-0000-0000-000000000002" "d0000000-0000-0000-0000-000000000012" "$cross_barcode" "$result_dir/cross-2" & p2=$!
call_manual_rpc "d0000000-0000-0000-0000-000000000003" "d0000000-0000-0000-0000-000000000013" "$cross_barcode" "$result_dir/cross-3" & p3=$!
call_manual_rpc "d0000000-0000-0000-0000-000000000004" "d0000000-0000-0000-0000-000000000014" "$cross_barcode" "$result_dir/cross-4" & p4=$!
wait "$p1" "$p2" "$p3" "$p4"

cross_counts="$(query "select
  (select count(*) from public.catalog_product_barcodes where barcode = '$cross_barcode'),
  (select count(distinct product.catalog_product_id) from public.products product join public.product_barcodes mapping on mapping.product_id = product.id where mapping.barcode = '$cross_barcode'),
  (select count(distinct product.shop_id) from public.products product join public.product_barcodes mapping on mapping.product_id = product.id where mapping.barcode = '$cross_barcode');")"
if [ "$cross_counts" != "1|1|4" ]; then
  echo "cross-shop concurrency failed: $cross_counts" >&2
  exit 1
fi

echo "PASS same-shop=1|1|1 cross-shop=1|1|4"
