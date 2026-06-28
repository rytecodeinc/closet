-- Redress: relationship-aware wardrobe list for outfit suggestions.
-- Requires SUPABASE_WARDROBES_VISIBILITY.sql and SUPABASE_FRIENDSHIPS_TABLE.sql applied.
-- Run in Supabase SQL Editor.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS allow_outfit_suggestions boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.user_profiles.allow_outfit_suggestions IS
  'When false, other users cannot suggest outfits (Redress) for this profile.';

DROP FUNCTION IF EXISTS public.get_redress_wardrobes(uuid);
DROP FUNCTION IF EXISTS public.get_redress_wardrobe_items(uuid, uuid);

-- Wardrobes a signed-in viewer may use when composing a Redress outfit for p_recipient_id.
-- Friends (accepted, either direction): visibility IN (public, friends).
-- Non-friends: visibility = public only. Private wardrobes are never returned.
-- Returns no rows when: unauthenticated, self, recipient opted out, or users are blocked.
CREATE OR REPLACE FUNCTION public.get_redress_wardrobes(p_recipient_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  type text,
  visibility text,
  is_default boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH viewer AS (
    SELECT auth.uid() AS uid
  ),
  recipient_allowed AS (
    SELECT up.user_id
    FROM public.user_profiles up
    WHERE up.user_id = p_recipient_id
      AND COALESCE(up.allow_outfit_suggestions, true) = true
  ),
  viewer_blocked AS (
    SELECT 1
    FROM public.friendships f
    CROSS JOIN viewer v
    WHERE v.uid IS NOT NULL
      AND f.status = 'blocked'
      AND (
        (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
        OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
      )
  ),
  viewer_is_friend AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.friendships f
      CROSS JOIN viewer v
      WHERE v.uid IS NOT NULL
        AND f.status = 'accepted'
        AND (
          (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
          OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
        )
    ) AS value
  )
  SELECT w.id, w.name, w.type, w.visibility, w.is_default
  FROM public.wardrobes w
  CROSS JOIN viewer v
  CROSS JOIN recipient_allowed r
  CROSS JOIN viewer_is_friend f
  WHERE v.uid IS NOT NULL
    AND v.uid <> p_recipient_id
    AND NOT EXISTS (SELECT 1 FROM viewer_blocked)
    AND w.user_id = p_recipient_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND (
      w.visibility = 'public'
      OR (f.value AND w.visibility = 'friends')
    )
  ORDER BY lower(coalesce(w.type, '')), w.is_default DESC, w.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_redress_wardrobes(uuid) TO authenticated;

-- Items in a wardrobe the viewer may use for Redress (same access gate as get_redress_wardrobes).
-- Returns no rows when the wardrobe is private, friends-only to a non-friend, or access is denied.
CREATE OR REPLACE FUNCTION public.get_redress_wardrobe_items(p_recipient_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  item_id uuid,
  name text,
  thumbnail_url text,
  image_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH viewer AS (
    SELECT auth.uid() AS uid
  ),
  recipient_allowed AS (
    SELECT up.user_id
    FROM public.user_profiles up
    WHERE up.user_id = p_recipient_id
      AND COALESCE(up.allow_outfit_suggestions, true) = true
  ),
  viewer_blocked AS (
    SELECT 1
    FROM public.friendships f
    CROSS JOIN viewer v
    WHERE v.uid IS NOT NULL
      AND f.status = 'blocked'
      AND (
        (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
        OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
      )
  ),
  viewer_is_friend AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.friendships f
      CROSS JOIN viewer v
      WHERE v.uid IS NOT NULL
        AND f.status = 'accepted'
        AND (
          (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
          OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
        )
    ) AS value
  ),
  allowed_wardrobe AS (
    SELECT w.id
    FROM public.wardrobes w
    CROSS JOIN viewer v
    CROSS JOIN recipient_allowed r
    CROSS JOIN viewer_is_friend f
    WHERE v.uid IS NOT NULL
      AND v.uid <> p_recipient_id
      AND NOT EXISTS (SELECT 1 FROM viewer_blocked)
      AND w.id = p_wardrobe_id
      AND w.user_id = p_recipient_id
      AND COALESCE(w.is_soft_deleted, false) = false
      AND (
        w.visibility = 'public'
        OR (f.value AND w.visibility = 'friends')
      )
  )
  SELECT
    i.id AS item_id,
    i.name,
    COALESCE(
      primary_photo.thumbnail_url,
      primary_photo.image_url,
      any_photo.thumbnail_url,
      any_photo.image_url
    ) AS thumbnail_url,
    COALESCE(primary_photo.image_url, any_photo.image_url) AS image_url
  FROM allowed_wardrobe aw
  INNER JOIN public.wardrobes w ON w.id = aw.id
  INNER JOIN public.item_wardrobes iw ON iw.wardrobe_id = w.id
  INNER JOIN public.items i ON i.id = iw.item_id
  LEFT JOIN LATERAL (
    SELECT p.thumbnail_url, p.image_url
    FROM public.item_photos p
    WHERE p.item_id = i.id
      AND COALESCE(p.is_primary, false) = true
    ORDER BY p.created_at NULLS LAST
    LIMIT 1
  ) primary_photo ON true
  LEFT JOIN LATERAL (
    SELECT p.thumbnail_url, p.image_url
    FROM public.item_photos p
    WHERE p.item_id = i.id
    ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
    LIMIT 1
  ) any_photo ON true
  WHERE i.user_id = p_recipient_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
  ORDER BY i.created_at DESC NULLS LAST, i.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_redress_wardrobe_items(uuid, uuid) TO authenticated;
