-- Use only before this slice contains production data. This intentionally
-- refuses to preserve rows because no prior schema exists to receive them.
drop function if exists public.create_product_for_barcode(uuid, text, text, text, text, text, text);
drop function if exists public.create_shop_with_owner(text);
drop function if exists public.is_shop_member(uuid);
drop trigger if exists products_set_updated_at on public.products;
drop trigger if exists shops_set_updated_at on public.shops;
drop function if exists public.set_updated_at();
drop table if exists public.product_barcodes;
drop table if exists public.products;
drop table if exists public.shop_memberships;
drop table if exists public.shops;
