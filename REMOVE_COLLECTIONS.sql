-- SQL script to remove Collections functionality from Supabase
-- Collections have been replaced by Wardrobes in the app
-- Run this script in Supabase SQL Editor

-- Step 1: Drop the item_collections junction table (if it exists)
DROP TABLE IF EXISTS item_collections CASCADE;

-- Step 2: Drop the collections table (if it exists)
-- Note: This will permanently delete all collection data
-- Only run this if you're sure you want to remove all collections
DROP TABLE IF EXISTS collections CASCADE;

-- Step 3: Drop any RLS policies related to collections (if they exist)
-- Note: These should be automatically dropped with the tables above,
-- but included here for completeness

-- Verify tables are removed
-- Run these queries to confirm:
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('collections', 'item_collections');
-- Should return 0 rows

