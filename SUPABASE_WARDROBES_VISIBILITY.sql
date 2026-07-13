-- Per-wardrobe visibility for profile sharing: public (default), private, or friends-only.
-- Run in Supabase SQL Editor.
-- For a full backfill + friend-aware RPCs, prefer SUPABASE_WARDROBES_VISIBILITY_BACKFILL.sql.

ALTER TABLE public.wardrobes
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

COMMENT ON COLUMN public.wardrobes.visibility IS
  'Who can view this wardrobe on a user profile: public, private, or friends.';

-- Backfill any pre-migration rows (should be covered by DEFAULT, but safe to run).
UPDATE public.wardrobes
SET visibility = 'public'
WHERE visibility IS NULL OR visibility = '';

-- Enforce allowed values.
ALTER TABLE public.wardrobes
  DROP CONSTRAINT IF EXISTS wardrobes_visibility_check;

ALTER TABLE public.wardrobes
  ADD CONSTRAINT wardrobes_visibility_check
  CHECK (visibility IN ('public', 'private', 'friends'));
