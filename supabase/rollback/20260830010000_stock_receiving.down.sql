-- Use only when intentionally removing this slice. Dropping these append-only
-- records destroys receiving history, so production rollback requires an
-- explicit data-retention/export decision first.
drop function if exists public.receive_product_stock(uuid, uuid, integer, date, text, text);
drop trigger if exists batches_set_updated_at on public.batches;
drop table if exists public.inventory_movements;
drop table if exists public.batches;
