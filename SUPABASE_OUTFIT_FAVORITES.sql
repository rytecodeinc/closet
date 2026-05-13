-- Add favorites support for outfits
-- Run this in Supabase SQL editor (or your migrations)

ALTER TABLE outfits
ADD COLUMN IF NOT EXISTS is_favorite boolean NOT NULL DEFAULT false;

