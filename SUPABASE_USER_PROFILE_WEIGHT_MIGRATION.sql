-- Migration: Add weight columns to user_profiles table
-- This allows syncing weight data across devices

-- Add weight_kg column (nullable, as users may not have set their weight)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS weight_kg DOUBLE PRECISION;

-- Add weight_unit column (nullable, as users may not have set their weight)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS weight_unit TEXT;

-- Add comment for documentation
COMMENT ON COLUMN user_profiles.weight_kg IS 'User weight in kilograms';
COMMENT ON COLUMN user_profiles.weight_unit IS 'Unit of measurement (e.g., "kg", "lbs")';

