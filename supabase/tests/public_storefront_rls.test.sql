begin;
select plan(43);

insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'manager-a@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'worker-a@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'owner-b@example.test'),
  ('10000000-0000-0000-0000-000000000005', 'customer@example.test');

insert into public.shops (id, name, currency_code)
values
  ('20000000-0000-0000-0000-000000000001', 'Public Shop A', 'QAR'),
  ('20000000-0000-0000-0000-000000000002', 'Private Shop B', 'QAR');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'manager'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'worker'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'owner');

update public.public_shop_profiles
set is_enabled = shop_id = '20000000-0000-0000-0000-000000000001',
    description = 'Customer-safe description',
    area = 'Doha';

insert into public.products (id, shop_id, name, source)
values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Private Product A1', 'local_manual'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Private Product A2', 'local_manual'),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 'Private Product B', 'local_manual');

insert into public.published_product_listings (
  id, shop_id, product_id, display_name, price_minor, currency_code, is_published
)
values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Published A1', 1000, 'QAR', true),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', 'Unpublished A2', 1200, 'QAR', false),
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', 'Published B', 900, 'QAR', true);

insert into public.deals (
  id, shop_id, listing_id, offer_price_minor, starts_at, ends_at, is_enabled, title
)
values
  ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 800, now() - interval '1 hour', now() + interval '1 hour', true, 'Active'),
  ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 750, now() + interval '2 hours', now() + interval '3 hours', true, 'Future'),
  ('50000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 700, now() - interval '3 hours', now() - interval '2 hours', true, 'Expired'),
  ('50000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', 700, now() - interval '1 hour', now() + interval '1 hour', true, 'Private shop');

select has_table('public', 'catalog_products', 'global catalog products table exists');
select has_table('public', 'catalog_product_barcodes', 'global catalog barcodes table exists');
select has_table('public', 'public_shop_profiles', 'public shop profiles table exists');
select has_table('public', 'published_product_listings', 'published listings table exists');
select has_table('public', 'deals', 'deals table exists');

set local role anon;

select results_eq(
  $$select display_name from public.public_storefront_shops order by display_name$$,
  $$values ('Public Shop A'::text)$$,
  'anonymous customers see only enabled storefronts'
);
select results_eq(
  $$select display_name from public.public_storefront_listings order by display_name$$,
  $$values ('Published A1'::text)$$,
  'anonymous customers see only explicitly published listings in enabled shops'
);
select results_eq(
  $$select title from public.public_storefront_deals order by title$$,
  $$values ('Active'::text)$$,
  'database time and publication RLS expose only the active public deal'
);
select throws_ok($$select * from public.products$$, '42501', null, 'anonymous cannot read private Products');
select throws_ok($$select * from public.batches$$, '42501', null, 'anonymous cannot read Batches');
select throws_ok($$select * from public.inventory_movements$$, '42501', null, 'anonymous cannot read movements');
select throws_ok($$select * from public.shop_memberships$$, '42501', null, 'anonymous cannot read members');
select throws_ok($$select * from public.shops$$, '42501', null, 'anonymous cannot read private shops');
select throws_ok(
  $$insert into public.public_shop_profiles (shop_id, display_name) values ('20000000-0000-0000-0000-000000000001', 'Changed')$$,
  '42501', null, 'anonymous cannot mutate profiles'
);
select throws_ok(
  $$update public.published_product_listings set display_name = 'Changed' where id = '40000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'anonymous cannot mutate listings'
);
select throws_ok(
  $$update public.deals set is_enabled = false where id = '50000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'anonymous cannot mutate deals'
);
select throws_ok($$select * from public.catalog_products$$, '42501', null, 'anonymous cannot read internal global catalog');
select throws_ok($$select * from public.catalog_product_barcodes$$, '42501', null, 'anonymous cannot read global barcode mapping');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$select display_name from public.public_storefront_shops$$,
  $$values ('Public Shop A'::text)$$,
  'authenticated non-member customer has the same public shop read'
);
select results_eq(
  $$select display_name from public.public_storefront_listings$$,
  $$values ('Published A1'::text)$$,
  'authenticated non-member customer has the same public listing read'
);
select results_eq(
  $$select title from public.public_storefront_deals$$,
  $$values ('Active'::text)$$,
  'authenticated non-member customer has the same active-deal read'
);
select is((select count(*) from public.batches), 0::bigint, 'customer reads no private Batches');
select is((select count(*) from public.inventory_movements), 0::bigint, 'customer reads no private movements');
select results_eq(
  $$update public.published_product_listings set display_name = 'Customer change'
    where id = '40000000-0000-0000-0000-000000000001' returning id$$,
  $$select null::uuid where false$$,
  'customer cannot mutate listings'
);
select results_eq(
  $$update public.deals set is_enabled = false
    where id = '50000000-0000-0000-0000-000000000001' returning id$$,
  $$select null::uuid where false$$,
  'customer cannot mutate deals'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select results_eq(
  $$select
      (select count(*) from public.public_storefront_listings),
      (select count(*) from public.public_storefront_deals)$$,
  $$values (1::bigint, 1::bigint)$$,
  'owner browsing public views still sees only published and active customer rows'
);
select lives_ok(
  $$update public.public_shop_profiles set area = 'Doha Central' where shop_id = '20000000-0000-0000-0000-000000000001'$$,
  'owner can update own profile'
);
select lives_ok(
  $$update public.published_product_listings set description = 'Owner edit' where id = '40000000-0000-0000-0000-000000000001'$$,
  'owner can update own listing'
);
select lives_ok(
  $$update public.deals set title = 'Owner edit' where id = '50000000-0000-0000-0000-000000000001'$$,
  'owner can update own deal'
);
select results_eq(
  $$update public.public_shop_profiles set area = 'Blocked'
    where shop_id = '20000000-0000-0000-0000-000000000002' returning shop_id$$,
  $$select null::uuid where false$$,
  'Shop A owner cannot update Shop B profile'
);
select results_eq(
  $$update public.published_product_listings set description = 'Blocked'
    where id = '40000000-0000-0000-0000-000000000003' returning id$$,
  $$select null::uuid where false$$,
  'Shop A owner cannot update Shop B listing'
);
select results_eq(
  $$update public.deals set title = 'Blocked'
    where id = '50000000-0000-0000-0000-000000000004' returning id$$,
  $$select null::uuid where false$$,
  'Shop A owner cannot update Shop B deal'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select lives_ok(
  $$update public.public_shop_profiles set area = 'Manager edit' where shop_id = '20000000-0000-0000-0000-000000000001'$$,
  'manager can update own profile'
);
select lives_ok(
  $$update public.published_product_listings set description = 'Manager edit' where id = '40000000-0000-0000-0000-000000000001'$$,
  'manager can update own listing'
);
select lives_ok(
  $$update public.deals set title = 'Manager edit' where id = '50000000-0000-0000-0000-000000000001'$$,
  'manager can update own deal'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select results_eq(
  $$update public.public_shop_profiles set area = 'Worker edit'
    where shop_id = '20000000-0000-0000-0000-000000000001' returning shop_id$$,
  $$select null::uuid where false$$,
  'worker cannot update profile'
);
select results_eq(
  $$update public.published_product_listings set description = 'Worker edit'
    where id = '40000000-0000-0000-0000-000000000001' returning id$$,
  $$select null::uuid where false$$,
  'worker cannot update listing'
);
select results_eq(
  $$update public.deals set title = 'Worker edit'
    where id = '50000000-0000-0000-0000-000000000001' returning id$$,
  $$select null::uuid where false$$,
  'worker cannot update deal'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$insert into public.published_product_listings (shop_id, product_id, display_name, price_minor, currency_code)
    values ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', 'Cross-shop', 500, 'QAR')$$,
  '23503', null, 'listing cannot reference another shop Product'
);
select throws_ok(
  $$insert into public.deals (shop_id, listing_id, offer_price_minor, starts_at, ends_at)
    values ('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003', 500, now(), now() + interval '1 day')$$,
  '23503', null, 'deal cannot reference another shop listing'
);
select throws_ok(
  $$insert into public.deals (shop_id, listing_id, offer_price_minor, starts_at, ends_at)
    values ('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 650, now() - interval '30 minutes', now() + interval '30 minutes')$$,
  '23P01', null, 'enabled deals cannot overlap'
);
select throws_ok(
  $$insert into public.deals (shop_id, listing_id, offer_price_minor, starts_at, ends_at)
    values ('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 1000, now() + interval '4 hours', now() + interval '5 hours')$$,
  '22023', null, 'offer price must be below listing price'
);
select throws_ok(
  $$update public.published_product_listings set price_minor = 700 where id = '40000000-0000-0000-0000-000000000001'$$,
  '22023', null, 'listing price cannot invalidate an enabled offer'
);

select * from finish();
rollback;
