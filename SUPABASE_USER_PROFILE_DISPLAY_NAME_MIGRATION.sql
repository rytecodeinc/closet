-- Migration: Add display_name column to user_profiles table
-- This allows users to set a display name separate from their username

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS display_name TEXT;

-- Note: username column should already exist in user_profiles table
-- If it doesn't, uncomment the line below:
-- ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS username TEXT;

