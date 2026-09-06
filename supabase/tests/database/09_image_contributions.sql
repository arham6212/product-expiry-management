begin;
select plan(20);
\set u1 '11111111-1111-1111-1111-111111111111'
\set u2 '22222222-2222-2222-2222-222222222222'
\set s1 '33333333-3333-3333-3333-333333333333'
\set c1 '44444444-4444-4444-4444-444444444444'
\set c2 '44444444-4444-4444-4444-444444444445'
\set p1 '55555555-5555-5555-5555-555555555555'

insert into auth.users (id, role, aud) values (:'u1','authenticated','authenticated'),(:'u2','authenticated','authenticated');
insert into public.shops (id,name) values (:'s1','Image Test Shop');
insert into public.shop_memberships (shop_id,user_id,role) values (:'s1',:'u1','owner'),(:'s1',:'u2','worker');
insert into public.catalog_products (id,canonical_name,source) values (:'c1','Linked','open_food_facts'),(:'c2','Unrelated','open_food_facts');
insert into public.products (id,shop_id,name,source,catalog_product_id) values (:'p1',:'s1','Shop Product','local_manual',:'c1');

select has_table('public','catalog_product_image_contributions','contribution table exists');
select has_column('public','catalog_product_image_contributions','mime_type','authoritative MIME is stored');
select ok(not has_table_privilege('authenticated','public.catalog_product_image_contributions','INSERT'),'authenticated cannot insert');
select ok(not has_table_privilege('authenticated','public.catalog_product_image_contributions','UPDATE'),'authenticated cannot update');
select ok(not has_table_privilege('authenticated','public.catalog_product_image_contributions','DELETE'),'authenticated cannot delete');
select ok(not has_function_privilege('authenticated','public.contribute_catalog_product_image(uuid,uuid,text,text,text,text)','EXECUTE'),'legacy metadata RPC is retired');
select ok(not has_function_privilege('authenticated','public.record_verified_catalog_product_image_contribution(uuid,uuid,uuid,text,text,text,text,text,bigint,integer,integer)','EXECUTE'),'record RPC is service-only');
select ok(not has_function_privilege('authenticated','public.set_catalog_product_canonical_image(uuid)','EXECUTE'),'promotion is service-only');

select throws_ok($$select * from public.record_verified_catalog_product_image_contribution('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','bad-mime','pub-bad','1','https://res.cloudinary.com/demo/image/upload/bad.svg','image/svg+xml',100,10,10)$$,'Verified image metadata is outside allowed limits','invalid MIME is rejected');
select throws_ok($$select * from public.record_verified_catalog_product_image_contribution('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','too-big','pub-big','1','https://res.cloudinary.com/demo/image/upload/big.jpg','image/jpeg',5242881,10,10)$$,'Verified image metadata is outside allowed limits','oversized image is rejected');
select throws_ok($$select * from public.record_verified_catalog_product_image_contribution('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444445','unrelated','pub-other','1','https://res.cloudinary.com/demo/image/upload/other.jpg','image/jpeg',100,10,10)$$,'Shop has no Product linked to this CatalogProduct','unrelated catalog product is rejected');
select lives_ok($$select * from public.record_verified_catalog_product_image_contribution('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','asset-1','product-catalog/contributions/44444444-4444-4444-4444-444444444444/photo','42','https://res.cloudinary.com/demo/image/upload/v42/photo.jpg','image/jpeg',1024,1200,900)$$,'trusted contribution succeeds');
select results_eq($$select status,is_canonical from public.catalog_product_image_contributions where provider_asset_id='asset-1'$$,$$values ('pending'::text,false)$$,'new contribution is pending and non-canonical');
select results_eq(
  $$select count(*) from public.record_verified_catalog_product_image_contribution('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','asset-1','product-catalog/contributions/44444444-4444-4444-4444-444444444444/photo','42','https://res.cloudinary.com/demo/image/upload/v42/photo.jpg','image/jpeg',1024,1200,900)$$,
  $$values (1::bigint)$$,
  'an exact verified retry returns the existing contribution');

select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111"}',true);
select set_config('role','authenticated',true);
select results_eq($$select provider_asset_id from public.catalog_product_image_contributions$$,$$values ('asset-1'::text)$$,'uploader member can read own row');
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222"}',true);
select is_empty($$select provider_asset_id from public.catalog_product_image_contributions$$,'another member cannot read it');

select set_config('role','postgres',true);
delete from public.shop_memberships where shop_id=:'s1' and user_id=:'u1';
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111"}',true);
select set_config('role','authenticated',true);
select is_empty($$select provider_asset_id from public.catalog_product_image_contributions$$,'uploader loses access after membership removal');
select set_config('role','postgres',true);
select throws_ok($$select * from public.record_verified_catalog_product_image_contribution('22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','asset-1','product-catalog/contributions/44444444-4444-4444-4444-444444444444/photo','42','https://res.cloudinary.com/demo/image/upload/v42/photo.jpg','image/jpeg',1024,1200,900)$$,'Provider asset is already bound to another contribution','asset cannot be rebound');
prepare promote_image as select public.set_catalog_product_canonical_image(id) from public.catalog_product_image_contributions where provider_asset_id='asset-1';
select lives_ok('promote_image','service authority can promote');
select results_eq($$select c.status,c.is_canonical,p.image_url from public.catalog_product_image_contributions c join public.catalog_products p on p.id=c.catalog_product_id where c.provider_asset_id='asset-1'$$,$$values ('approved'::text,true,'https://res.cloudinary.com/demo/image/upload/v42/photo.jpg'::text)$$,'promotion updates canonical image atomically');
select * from finish();
rollback;
