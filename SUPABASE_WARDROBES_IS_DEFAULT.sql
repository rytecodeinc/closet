-- Wardrobes: mark canonical default closet / wishlist per user (app + Core Data mirror).
-- Run in Supabase SQL editor after reviewing RLS (wardrobes policies unchanged by column add).

ALTER TABLE public.wardrobes
    ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.wardrobes.is_default IS 'True for the single canonical closet (type=closet) or wishlist (type=wishlist) row per user; enforced in app + optional DB indexes below.';

-- At most one default closet and one default wishlist per user (case-insensitive type).
CREATE UNIQUE INDEX IF NOT EXISTS wardrobes_one_default_closet_per_user
    ON public.wardrobes (user_id)
    WHERE is_default = true AND lower(coalesce(type, '')) = 'closet';

CREATE UNIQUE INDEX IF NOT EXISTS wardrobes_one_default_wishlist_per_user
    ON public.wardrobes (user_id)
    WHERE is_default = true AND lower(coalesce(type, '')) = 'wishlist';
