-- Extend get_visible_item_detail with paired_items + outfits for ReadOnlyItemDetailView.
-- Run after friend-aware get_visible_wardrobe_* RPCs (e.g. SUPABASE_WARDROBES_VISIBILITY_BACKFILL.sql).
-- Visibility: public (everyone), friends (accepted friends), owner (own profile).
-- Item may load from any wardrobe visible to the viewer (pair navigation across wardrobes).
-- Outfits for non-owners are scoped to outfits visible in p_wardrobe_id.

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
