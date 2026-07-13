-- Backfill wardrobe visibility + friend-aware profile RPCs.
-- Fixes beta-era wardrobes missing/invalid visibility ("No public wardrobes" for friends).
-- Safe to re-run.

-- 1) Ensure column exists
ALTER TABLE public.wardrobes
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

-- 2) Migrate legacy / invalid values → public
UPDATE public.wardrobes
SET visibility = 'public'
WHERE visibility IS NULL
   OR btrim(visibility) = ''
   OR lower(btrim(visibility)) NOT IN ('public', 'private', 'friends');

UPDATE public.wardrobes
SET visibility = lower(btrim(visibility))
WHERE visibility IS DISTINCT FROM lower(btrim(visibility))
  AND lower(btrim(visibility)) IN ('public', 'private', 'friends');

ALTER TABLE public.wardrobes
  DROP CONSTRAINT IF EXISTS wardrobes_visibility_check;

ALTER TABLE public.wardrobes
  ADD CONSTRAINT wardrobes_visibility_check
  CHECK (visibility IN ('public', 'private', 'friends'));

-- Shared visibility predicate helper pattern:
-- public → everyone; friends → accepted friends only; private → never via these RPCs.

-- 3) Wardrobe list
CREATE OR REPLACE FUNCTION public.get_visible_wardrobes(p_user_id uuid)
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
  SELECT w.id, w.name, w.type, w.visibility, w.is_default
  FROM public.wardrobes w
  CROSS JOIN viewer_is_friend f
  WHERE w.user_id = p_user_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND (
      w.visibility = 'public'
      OR (f.value AND w.visibility = 'friends')
    )
  ORDER BY lower(coalesce(w.type, '')), w.is_default DESC, w.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_wardrobes(uuid) TO authenticated;

-- 4) Items in a visible wardrobe
CREATE OR REPLACE FUNCTION public.get_visible_wardrobe_items(p_user_id uuid, p_wardrobe_id uuid)
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
  FROM public.wardrobes w
  CROSS JOIN viewer_is_friend f
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
  WHERE w.id = p_wardrobe_id
    AND w.user_id = p_user_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND (
      w.visibility = 'public'
      OR (f.value AND w.visibility = 'friends')
    )
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
  ORDER BY i.created_at DESC NULLS LAST, i.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_wardrobe_items(uuid, uuid) TO authenticated;

-- 5) Outfits (preserve closet/wishlist membership rules; friend-aware wardrobe gate)
CREATE OR REPLACE FUNCTION public.get_visible_wardrobe_outfits(p_user_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  outfit_id uuid,
  name text,
  image_url text,
  worn_image_url text
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
  ),
  target_wardrobe AS (
    SELECT w.id, lower(coalesce(w.type, '')) AS wardrobe_type
    FROM public.wardrobes w
    CROSS JOIN viewer_is_friend f
    WHERE w.id = p_wardrobe_id
      AND w.user_id = p_user_id
      AND COALESCE(w.is_soft_deleted, false) = false
      AND (
        w.visibility = 'public'
        OR (f.value AND w.visibility = 'friends')
      )
  ),
  outfit_items_active AS (
    SELECT oi.outfit_id, i.id AS item_id
    FROM public.outfit_items oi
    INNER JOIN public.items i ON i.id = oi.item_id
    WHERE i.user_id = p_user_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false
  )
  SELECT o.id AS outfit_id, o.name, o.image_url, o.worn_image_url
  FROM public.outfits o
  INNER JOIN target_wardrobe tw ON true
  WHERE o.user_id = p_user_id
    AND COALESCE(o.is_soft_deleted, false) = false
    AND COALESCE(o.is_draft, false) = false
    AND EXISTS (
      SELECT 1
      FROM outfit_items_active oia
      WHERE oia.outfit_id = o.id
    )
    AND (
      CASE
        WHEN tw.wardrobe_type = 'wishlist' THEN
          EXISTS (
            SELECT 1
            FROM outfit_items_active oia
            INNER JOIN public.item_wardrobes iw ON iw.item_id = oia.item_id AND iw.wardrobe_id = p_wardrobe_id
            WHERE oia.outfit_id = o.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM outfit_items_active oia
            WHERE oia.outfit_id = o.id
              AND EXISTS (
                SELECT 1
                FROM public.item_wardrobes iw2
                INNER JOIN public.wardrobes ww ON ww.id = iw2.wardrobe_id
                WHERE iw2.item_id = oia.item_id
                  AND lower(coalesce(ww.type, '')) = 'wishlist'
                  AND COALESCE(ww.is_soft_deleted, false) = false
              )
              AND NOT EXISTS (
                SELECT 1
                FROM public.item_wardrobes iw3
                WHERE iw3.item_id = oia.item_id
                  AND iw3.wardrobe_id = p_wardrobe_id
              )
          )
        ELSE
          NOT EXISTS (
            SELECT 1
            FROM outfit_items_active oia
            WHERE oia.outfit_id = o.id
              AND NOT EXISTS (
                SELECT 1
                FROM public.item_wardrobes iw
                WHERE iw.item_id = oia.item_id
                  AND iw.wardrobe_id = p_wardrobe_id
              )
          )
      END
    )
  ORDER BY o.created_at DESC NULLS LAST, o.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_wardrobe_outfits(uuid, uuid) TO authenticated;

-- 6) Item detail visibility gate
CREATE OR REPLACE FUNCTION public.get_visible_item_detail(p_user_id uuid, p_item_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  item_id uuid,
  name text,
  notes text,
  brand_name text,
  category_name text,
  subcategory_name text,
  size_value text,
  photos jsonb
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
  SELECT
    i.id AS item_id,
    i.name,
    i.notes,
    b.name AS brand_name,
    c.name AS category_name,
    sc.name AS subcategory_name,
    sz.value AS size_value,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'image_url', p.image_url,
            'thumbnail_url', p.thumbnail_url,
            'type', p.type,
            'is_primary', COALESCE(p.is_primary, false)
          )
          ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
        )
        FROM public.item_photos p
        WHERE p.item_id = i.id
      ),
      '[]'::jsonb
    ) AS photos
  FROM public.wardrobes w
  CROSS JOIN viewer_is_friend f
  INNER JOIN public.item_wardrobes iw ON iw.wardrobe_id = w.id AND iw.item_id = p_item_id
  INNER JOIN public.items i ON i.id = p_item_id
  LEFT JOIN public.brands b ON b.id = i.brand_id
  LEFT JOIN public.categories c ON c.id = i.category_id
  LEFT JOIN public.subcategories sc ON sc.id = i.subcategory_id
  LEFT JOIN public.sizes sz ON sz.id = i.size_id
  WHERE w.id = p_wardrobe_id
    AND w.user_id = p_user_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND (
      w.visibility = 'public'
      OR (f.value AND w.visibility = 'friends')
    )
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_item_detail(uuid, uuid, uuid) TO authenticated;
