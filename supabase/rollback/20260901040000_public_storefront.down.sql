drop view if exists public.public_storefront_deals;
drop view if exists public.public_storefront_listings;
drop view if exists public.public_storefront_shops;
drop trigger if exists published_product_listings_validate_price
  on public.published_product_listings;
drop trigger if exists deals_validate on public.deals;
drop trigger if exists shops_ensure_public_profile on public.shops;
drop function if exists public.validate_listing_price_change();
drop function if exists public.validate_deal();
drop function if exists public.can_manage_public_storefront(uuid);
drop function if exists public.ensure_public_shop_profile();
drop table if exists public.deals;
drop table if exists public.published_product_listings;
drop table if exists public.public_shop_profiles;
alter table public.products drop column if exists catalog_product_id;
drop table if exists public.catalog_product_barcodes;
drop table if exists public.catalog_products;
