-- Add wishlist / purchase lifecycle dates on items.
-- `created_at` stays the immutable record-creation time.

ALTER TABLE public.items
    ADD COLUMN IF NOT EXISTS wished_at timestamptz;

ALTER TABLE public.items
    ADD COLUMN IF NOT EXISTS purchased_at timestamptz;

COMMENT ON COLUMN public.items.wished_at IS 'When the item was first saved to a wishlist wardrobe.';
COMMENT ON COLUMN public.items.purchased_at IS 'When the item entered a closet wardrobe (direct add or moved from wishlist).';

-- Wishlist items: wished_at = created_at when missing.
UPDATE public.items i
SET wished_at = i.created_at
WHERE i.wished_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM public.item_wardrobes iw
      JOIN public.wardrobes w ON w.id = iw.wardrobe_id
      WHERE iw.item_id = i.id
        AND lower(coalesce(w.type, '')) = 'wishlist'
  );

-- Closet-only items: purchased_at = created_at when missing.
UPDATE public.items i
SET purchased_at = i.created_at
WHERE i.purchased_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM public.item_wardrobes iw
      JOIN public.wardrobes w ON w.id = iw.wardrobe_id
      WHERE iw.item_id = i.id
        AND lower(coalesce(w.type, '')) = 'closet'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM public.item_wardrobes iw2
      JOIN public.wardrobes w2 ON w2.id = iw2.wardrobe_id
      WHERE iw2.item_id = i.id
        AND lower(coalesce(w2.type, '')) = 'wishlist'
  );

-- Items now in closet that still have wished_at (moved from wishlist): purchased_at defaults to updated_at or created_at.
UPDATE public.items i
SET purchased_at = coalesce(i.updated_at, i.created_at)
WHERE i.purchased_at IS NULL
  AND i.wished_at IS NOT NULL
  AND EXISTS (
      SELECT 1
      FROM public.item_wardrobes iw
      JOIN public.wardrobes w ON w.id = iw.wardrobe_id
      WHERE iw.item_id = i.id
        AND lower(coalesce(w.type, '')) = 'closet'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM public.item_wardrobes iw2
      JOIN public.wardrobes w2 ON w2.id = iw2.wardrobe_id
      WHERE iw2.item_id = i.id
        AND lower(coalesce(w2.type, '')) = 'wishlist'
  );
