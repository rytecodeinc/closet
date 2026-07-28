-- Public profile read APIs (v1: public wardrobes only).
-- Requires SUPABASE_WARDROBES_VISIBILITY.sql applied.
-- Run in Supabase SQL Editor.

DROP FUNCTION IF EXISTS public.get_visible_wardrobes(uuid);
DROP FUNCTION IF EXISTS public.get_visible_wardrobe_items(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_visible_wardrobe_outfits(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_visible_item_detail(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_visible_outfit_detail(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.get_user_friend_count(uuid);

-- Friend count for any user (shown on public profiles).
CREATE OR REPLACE FUNCTION get_user_friend_count(p_user_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT COUNT(*)::integer
  FROM (
    SELECT f.id
    FROM friendships f
    WHERE f.status = 'accepted'
      AND f.user_id = p_user_id
    UNION ALL
    SELECT f.id
    FROM friendships f
    WHERE f.status = 'accepted'
      AND f.friend_user_id = p_user_id
  ) accepted;
$$;

GRANT EXECUTE ON FUNCTION get_user_friend_count(uuid) TO authenticated;

-- Wardrobes the viewer may see on another user's profile (public only in v1).
CREATE OR REPLACE FUNCTION get_visible_wardrobes(p_user_id uuid)
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
  SELECT w.id, w.name, w.type, w.visibility, w.is_default
  FROM wardrobes w
  WHERE w.user_id = p_user_id
    AND COALESCE(w.is_soft_deleted, false) = false
    AND w.visibility = 'public'
  ORDER BY lower(coalesce(w.type, '')), w.is_default DESC, w.name;
$$;

GRANT EXECUTE ON FUNCTION get_visible_wardrobes(uuid) TO authenticated;

-- Items in a public wardrobe (viewer must not receive private/friends wardrobes).
CREATE OR REPLACE FUNCTION get_visible_wardrobe_items(p_user_id uuid, p_wardrobe_id uuid)
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
  FROM wardrobes w
  INNER JOIN item_wardrobes iw ON iw.wardrobe_id = w.id
  INNER JOIN items i ON i.id = iw.item_id
  LEFT JOIN LATERAL (
    SELECT p.thumbnail_url, p.image_url
    FROM item_photos p
    WHERE p.item_id = i.id
      AND COALESCE(p.is_primary, false) = true
    ORDER BY p.created_at NULLS LAST
    LIMIT 1
  ) primary_photo ON true
  LEFT JOIN LATERAL (
    SELECT p.thumbnail_url, p.image_url
    FROM item_photos p
    WHERE p.item_id = i.id
    ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
    LIMIT 1
  ) any_photo ON true
  WHERE w.id = p_wardrobe_id
    AND w.user_id = p_user_id
    AND w.visibility = 'public'
    AND COALESCE(w.is_soft_deleted, false) = false
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
  ORDER BY i.created_at DESC NULLS LAST, i.name;
$$;

GRANT EXECUTE ON FUNCTION get_visible_wardrobe_items(uuid, uuid) TO authenticated;

-- Outfits visible in a public wardrobe (matches app closet/wishlist tab rules).
CREATE OR REPLACE FUNCTION get_visible_wardrobe_outfits(p_user_id uuid, p_wardrobe_id uuid)
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
  WITH target_wardrobe AS (
    SELECT w.id, lower(coalesce(w.type, '')) AS wardrobe_type
    FROM wardrobes w
    WHERE w.id = p_wardrobe_id
      AND w.user_id = p_user_id
      AND w.visibility = 'public'
      AND COALESCE(w.is_soft_deleted, false) = false
  ),
  outfit_items_active AS (
    SELECT oi.outfit_id, i.id AS item_id
    FROM outfit_items oi
    INNER JOIN items i ON i.id = oi.item_id
    WHERE i.user_id = p_user_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false
  )
  SELECT o.id AS outfit_id, o.name, o.image_url, o.worn_image_url
  FROM outfits o
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
            INNER JOIN item_wardrobes iw ON iw.item_id = oia.item_id AND iw.wardrobe_id = p_wardrobe_id
            WHERE oia.outfit_id = o.id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM outfit_items_active oia
            WHERE oia.outfit_id = o.id
              AND EXISTS (
                SELECT 1
                FROM item_wardrobes iw2
                INNER JOIN wardrobes ww ON ww.id = iw2.wardrobe_id
                WHERE iw2.item_id = oia.item_id
                  AND lower(coalesce(ww.type, '')) = 'wishlist'
                  AND COALESCE(ww.is_soft_deleted, false) = false
              )
              AND NOT EXISTS (
                SELECT 1
                FROM item_wardrobes iw3
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
                FROM item_wardrobes iw
                WHERE iw.item_id = oia.item_id
                  AND iw.wardrobe_id = p_wardrobe_id
              )
          )
      END
    )
  ORDER BY o.created_at DESC NULLS LAST, o.name;
$$;

GRANT EXECUTE ON FUNCTION get_visible_wardrobe_outfits(uuid, uuid) TO authenticated;

-- Read-only item detail when item is in a wardrobe visible to the viewer.
-- Includes paired_items + outfits; allows public + friends (+ owner).
-- Prefer running SUPABASE_VISIBLE_ITEM_DETAIL_PAIRS_OUTFITS.sql if upgrading alone.

DROP FUNCTION IF EXISTS public.get_visible_item_detail(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION get_visible_item_detail(p_user_id uuid, p_item_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  item_id uuid,
  name text,
  notes text,
  brand_name text,
  category_name text,
  subcategory_name text,
  size_value text,
  photos jsonb,
  paired_items jsonb,
  outfits jsonb
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
      FROM friendships f
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
        FROM item_photos p
        WHERE p.item_id = i.id
      ),
      '[]'::jsonb
    ) AS photos,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_id', pi.id,
            'name', pi.name,
            'thumbnail_url', COALESCE(primary_photo.thumbnail_url, primary_photo.image_url, any_photo.thumbnail_url, any_photo.image_url),
            'image_url', COALESCE(primary_photo.image_url, any_photo.image_url)
          )
          ORDER BY lower(coalesce(pi.name, ''))
        )
        FROM item_pairs ip
        INNER JOIN items pi ON pi.id = ip.paired_item_id
        CROSS JOIN viewer_is_friend f
        LEFT JOIN LATERAL (
          SELECT p.thumbnail_url, p.image_url
          FROM item_photos p
          WHERE p.item_id = pi.id
            AND COALESCE(p.is_primary, false) = true
          ORDER BY p.created_at NULLS LAST
          LIMIT 1
        ) primary_photo ON true
        LEFT JOIN LATERAL (
          SELECT p.thumbnail_url, p.image_url
          FROM item_photos p
          WHERE p.item_id = pi.id
          ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
          LIMIT 1
        ) any_photo ON true
        WHERE ip.item_id = i.id
          AND pi.user_id = p_user_id
          AND COALESCE(pi.is_soft_deleted, false) = false
          AND COALESCE(pi.is_draft, false) = false
          AND (
            p_user_id = auth.uid()
            OR EXISTS (
              SELECT 1
              FROM item_wardrobes iw2
              INNER JOIN wardrobes w2 ON w2.id = iw2.wardrobe_id
              WHERE iw2.item_id = pi.id
                AND w2.user_id = p_user_id
                AND COALESCE(w2.is_soft_deleted, false) = false
                AND (
                  w2.visibility = 'public'
                  OR (f.value AND w2.visibility = 'friends')
                )
            )
          )
      ),
      '[]'::jsonb
    ) AS paired_items,
    COALESCE(
      (
        CASE
          WHEN p_user_id = auth.uid() THEN (
            SELECT jsonb_agg(
              jsonb_build_object(
                'outfit_id', o.id,
                'name', o.name,
                'image_url', o.image_url,
                'worn_image_url', o.worn_image_url
              )
              ORDER BY o.created_at DESC NULLS LAST, lower(coalesce(o.name, ''))
            )
            FROM outfits o
            INNER JOIN outfit_items oi ON oi.outfit_id = o.id AND oi.item_id = i.id
            WHERE o.user_id = p_user_id
              AND COALESCE(o.is_soft_deleted, false) = false
              AND COALESCE(o.is_draft, false) = false
          )
          ELSE (
            SELECT jsonb_agg(
              jsonb_build_object(
                'outfit_id', vo.outfit_id,
                'name', vo.name,
                'image_url', vo.image_url,
                'worn_image_url', vo.worn_image_url
              )
              ORDER BY lower(coalesce(vo.name, ''))
            )
            FROM get_visible_wardrobe_outfits(p_user_id, p_wardrobe_id) vo
            WHERE EXISTS (
              SELECT 1
              FROM outfit_items oi
              WHERE oi.outfit_id = vo.outfit_id
                AND oi.item_id = i.id
            )
          )
        END
      ),
      '[]'::jsonb
    ) AS outfits
  FROM items i
  CROSS JOIN viewer_is_friend f
  LEFT JOIN brands b ON b.id = i.brand_id
  LEFT JOIN categories c ON c.id = i.category_id
  LEFT JOIN subcategories sc ON sc.id = i.subcategory_id
  LEFT JOIN sizes sz ON sz.id = i.size_id
  WHERE i.id = p_item_id
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false
    AND EXISTS (
      SELECT 1
      FROM item_wardrobes iw
      INNER JOIN wardrobes w ON w.id = iw.wardrobe_id
      WHERE iw.item_id = i.id
        AND w.user_id = p_user_id
        AND COALESCE(w.is_soft_deleted, false) = false
        AND (
          w.user_id = auth.uid()
          OR w.visibility = 'public'
          OR (f.value AND w.visibility = 'friends')
        )
    )
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION get_visible_item_detail(uuid, uuid, uuid) TO authenticated;

-- Read-only outfit detail for outfits visible in a public wardrobe.
-- Owner may also load their own outfits from any wardrobe they own (own Profile tab).
CREATE OR REPLACE FUNCTION get_visible_outfit_detail(p_user_id uuid, p_outfit_id uuid, p_wardrobe_id uuid)
RETURNS TABLE (
  outfit_id uuid,
  name text,
  notes text,
  image_url text,
  worn_image_url text,
  created_at timestamptz,
  item_thumbnails jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    o.id AS outfit_id,
    o.name,
    o.notes,
    o.image_url,
    o.worn_image_url,
    o.created_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_id', i.id,
            'name', i.name,
            'thumbnail_url', COALESCE(
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM item_photos p
                WHERE p.item_id = i.id
                  AND COALESCE(p.is_primary, false) = true
                LIMIT 1
              ),
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM item_photos p
                WHERE p.item_id = i.id
                ORDER BY p.created_at NULLS LAST
                LIMIT 1
              )
            )
          )
          ORDER BY oi.item_id
        )
        FROM outfit_items oi
        INNER JOIN items i ON i.id = oi.item_id
        WHERE oi.outfit_id = o.id
          AND COALESCE(i.is_soft_deleted, false) = false
          AND COALESCE(i.is_draft, false) = false
      ),
      '[]'::jsonb
    ) AS item_thumbnails
  FROM outfits o
  WHERE o.id = p_outfit_id
    AND o.user_id = p_user_id
    AND COALESCE(o.is_soft_deleted, false) = false
    AND COALESCE(o.is_draft, false) = false
    AND (
      EXISTS (
        SELECT 1
        FROM get_visible_wardrobe_outfits(p_user_id, p_wardrobe_id) vis
        WHERE vis.outfit_id = o.id
      )
      OR (
        p_user_id = auth.uid()
        AND EXISTS (
          SELECT 1
          FROM wardrobes w
          WHERE w.id = p_wardrobe_id
            AND w.user_id = p_user_id
            AND COALESCE(w.is_soft_deleted, false) = false
        )
      )
    )
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION get_visible_outfit_detail(uuid, uuid, uuid) TO authenticated;
