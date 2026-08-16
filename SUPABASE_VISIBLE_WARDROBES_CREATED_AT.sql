-- Add created_at to get_visible_wardrobes so clients can pick earliest closet/wishlist.
-- Safe to re-run. Requires prior friend-aware get_visible_wardrobes (visibility backfill).

DROP FUNCTION IF EXISTS public.get_visible_wardrobes(uuid);

CREATE OR REPLACE FUNCTION public.get_visible_wardrobes(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  type text,
  visibility text,
  is_default boolean,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH viewer AS (
    SELECT auth.uid() AS uid
  ),
  viewer_is_friend AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.friendships f
      CROSS JOIN viewer v
      WHERE v.uid IS NOT NULL
        AND f.status = 'accepted'
        AND (
          (f.user_id = v.uid AND f.friend_user_id = p_user_id)
          OR (f.friend_user_id = v.uid AND f.user_id = p_user_id)
        )
    ) AS value
  )
  SELECT w.id, w.name, w.type, w.visibility, w.is_default, w.created_at
  FROM public.wardrobes w
  CROSS JOIN viewer_is_friend f
  WHERE w.user_id = p_user_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND (
      w.visibility = 'public'
      OR (f.value AND w.visibility = 'friends')
    )
  ORDER BY w.created_at ASC NULLS LAST, lower(coalesce(w.type, '')), w.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_wardrobes(uuid) TO authenticated;
