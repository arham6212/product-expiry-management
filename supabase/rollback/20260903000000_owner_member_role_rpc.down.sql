-- This removes the B06 mutation interface. Role changes already made through
-- the RPC are business data and must be reviewed explicitly rather than
-- guessed or automatically reversed.
drop function if exists public.update_shop_member_role(uuid, uuid, text);
