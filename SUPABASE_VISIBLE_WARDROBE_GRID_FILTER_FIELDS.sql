-- Add filter/sort fields to visible wardrobe grid RPCs (friend-aware).
-- Run after SUPABASE_WARDROBES_VISIBILITY_BACKFILL.sql (or equivalent friend-aware versions).
-- Safe to re-run.

DROP FUNCTION IF EXISTS public.get_visible_wardrobe_items(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_visible_wardrobe_outfits(uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_visible_wardrobe_items(p_user_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  item_id uuid,
  name text,
  thumbnail_url text,
  image_url text,
  created_at timestamptz,
  brand_name text,
  category_name text,
  subcategory_name text,
  size_value text
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
    COALESCE(primary_photo.image_url, any_photo.image_url) AS image_url,
    i.created_at,
    b.name AS brand_name,
    c.name AS category_name,
    sc.name AS subcategory_name,
    sz.value AS size_value
  FROM public.wardrobes w
  CROSS JOIN viewer_is_friend f
  INNER JOIN public.item_wardrobes iw ON iw.wardrobe_id = w.id
  INNER JOIN public.items i ON i.id = iw.item_id
  LEFT JOIN public.brands b ON b.id = i.brand_id
  LEFT JOIN public.categories c ON c.id = i.category_id
  LEFT JOIN public.subcategories sc ON sc.id = i.subcategory_id
  LEFT JOIN public.sizes sz ON sz.id = i.size_id
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
      OR w.user_id = auth.uid()
    )
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
  ORDER BY i.created_at DESC NULLS LAST, i.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_wardrobe_items(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_visible_wardrobe_outfits(p_user_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  outfit_id uuid,
  name text,
  image_url text,
  worn_image_url text,
  created_at timestamptz,
  category_name text
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
        OR w.user_id = auth.uid()
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
  SELECT
    o.id AS outfit_id,
    o.name,
    o.image_url,
    o.worn_image_url,
    o.created_at,
    oc.name AS category_name
  FROM public.outfits o
  INNER JOIN target_wardrobe tw ON true
  LEFT JOIN public.outfit_categories oc ON oc.id = o.category_id
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
