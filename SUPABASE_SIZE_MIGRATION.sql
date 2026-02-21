-- Migration: Make sizes independent of categories
-- This migration removes the category dependency from sizes table

-- Step 1: Drop the foreign key constraint if it exists
ALTER TABLE sizes 
DROP CONSTRAINT IF EXISTS sizes_category_id_fkey;

-- Step 2: Drop the unique constraint that includes category_id
-- The old constraint was likely: UNIQUE (category_id, value, scale)
ALTER TABLE sizes 
DROP CONSTRAINT IF EXISTS sizes_category_id_value_scale_key;

-- Step 3: Make category_id nullable (if it's not already)
ALTER TABLE sizes 
ALTER COLUMN category_id DROP NOT NULL;

-- Step 4: Create a new unique constraint without category_id
-- Sizes are now unique by (user_id, value, scale)
-- This allows the same size value/scale combination per user
CREATE UNIQUE INDEX IF NOT EXISTS sizes_user_id_value_scale_unique 
ON sizes (user_id, value, scale) 
WHERE value IS NOT NULL AND scale IS NOT NULL;

-- Step 5: Update any existing sizes to have NULL category_id
-- (Optional - only if you want to clear existing category references)
-- UPDATE sizes SET category_id = NULL WHERE category_id IS NOT NULL;

-- Verification queries (run these to check the migration):
-- SELECT column_name, is_nullable, data_type 
-- FROM information_schema.columns 
-- WHERE table_name = 'sizes' AND column_name = 'category_id';

-- SELECT constraint_name, constraint_type 
-- FROM information_schema.table_constraints 
-- WHERE table_name = 'sizes';

