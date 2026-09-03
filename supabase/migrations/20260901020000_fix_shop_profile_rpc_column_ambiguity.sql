-- Correct the owner-facing member profile RPCs without changing their public
-- contracts or authorization behavior. RETURNS TABLE output names are PL/pgSQL
-- variables, so every table column must be qualified to avoid error 42702.

CREATE OR REPLACE FUNCTION public.get_shop_pending_requests_with_users(target_shop_id uuid)
RETURNS TABLE (
  request_id uuid,
  user_id uuid,
  email text,
  status text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

CREATE OR REPLACE FUNCTION public.get_shop_members_with_users(target_shop_id uuid)
RETURNS TABLE (
  user_id uuid,
  email text,
  role text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

GRANT EXECUTE ON FUNCTION public.get_shop_pending_requests_with_users(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_shop_members_with_users(uuid) TO authenticated;
