-- Public profile fields for notification actors (and similar).
-- RLS on user_profiles is own-row only; this SECURITY DEFINER returns non-sensitive columns.
-- Run in Supabase SQL Editor.

DROP FUNCTION IF EXISTS public.get_public_profiles(uuid[]);

CREATE OR REPLACE FUNCTION public.get_public_profiles(p_user_ids uuid[])
RETURNS TABLE (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT up.user_id, up.username, up.display_name, up.avatar_url
  FROM public.user_profiles up
  WHERE up.user_id = ANY (p_user_ids)
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) TO authenticated;
