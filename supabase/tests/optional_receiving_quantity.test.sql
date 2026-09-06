begin;
select no_plan();
insert into auth.users(id,email) values ('eeeeeeee-0000-0000-0000-000000000001','optional-receiver@example.test');
insert into public.shops(id,name) values ('eeeeeeee-0000-0000-0000-000000000002','Optional receiving');
insert into public.shop_memberships(shop_id,user_id,role) values
('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000001','owner');
insert into public.products(id,shop_id,name,source) values
('eeeeeeee-0000-0000-0000-000000000003','eeeeeeee-0000-0000-0000-000000000002','Test product','local_manual');
set local role authenticated;
select set_config('request.jwt.claim.sub','eeeeeeee-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select results_eq(
$$select batch_current_quantity,movement_quantity_delta,was_duplicate from public.receive_product_stock(
'eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',7,'2027-01-01',null,'known',725)$$,
$$values (7,7,false)$$,'known receiving remains compatible');
select results_eq(
$$select batch_current_quantity,movement_quantity_delta,was_duplicate from public.receive_product_stock(
'eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',null,'2027-02-01',null,'unknown',725)$$,
$$values (null::integer,null::integer,false)$$,'unknown quantity creates a batch and audited null received movement');
select results_eq(
$$select batch_current_quantity,movement_quantity_delta,was_duplicate from public.receive_product_stock(
'eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',null,'2027-02-01',null,'unknown',725)$$,
$$values (null::integer,null::integer,true)$$,'exact unknown retry deduplicates');
select throws_ok(
$$select * from public.receive_product_stock('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',1,'2027-02-01',null,'unknown',725)$$,
'23505',null,'unknown to known under the same key conflicts');
select is((select count(*) from public.batches where shop_id='eeeeeeee-0000-0000-0000-000000000002'),2::bigint,'retry never creates an extra batch');
select is((select count(*) from public.inventory_movements where shop_id='eeeeeeee-0000-0000-0000-000000000002'),2::bigint,'every receipt has exactly one movement');
select results_eq(
$$select current_quantity from public.get_expiry_dashboard('eeeeeeee-0000-0000-0000-000000000002') order by expiry_date$$,
$$values (7),(null::integer)$$,'expiry dashboard retains known and unknown quantity batches');
select throws_ok(
$$select * from public.receive_product_stock('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',null,null,null,'missing-expiry',725)$$,
'22023',null,'unknown quantity still requires expiry');
select throws_ok(
$$select * from public.receive_product_stock('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',null,'2027-02-01',null,'missing-price',null)$$,
'22023',null,'unknown quantity still requires price');
select throws_ok(
$$select * from public.receive_product_stock('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',0,'2027-02-01',null,'zero',725)$$,
'22023',null,'zero is not an unknown quantity');
select throws_ok(
$$select * from public.receive_product_stock('eeeeeeee-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000003',-1,'2027-02-01',null,'negative',725)$$,
'22023',null,'negative quantities remain invalid');
reset role;
select throws_ok(
$$insert into public.inventory_movements(shop_id,batch_id,movement_type,quantity_delta,created_by,idempotency_key)
select shop_id,id,'sold',null,'eeeeeeee-0000-0000-0000-000000000001','invalid-null-sold' from public.batches where shop_id='eeeeeeee-0000-0000-0000-000000000002' limit 1$$,
'23514',null,'only received movements allow unknown quantity');
select * from finish();
rollback;
