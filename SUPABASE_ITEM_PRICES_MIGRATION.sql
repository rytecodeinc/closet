-- Migration: Make item_id the primary key of item_prices
-- Reason: Each item has exactly one price. The previous schema used a separate
-- UUID `id` as the primary key, which caused the Swift sync to insert a new row
-- on every sync (because a fresh UUID was generated each time, bypassing the
-- upsert conflict check). This migration fixes the schema to match the intent.
--
-- Run this in the Supabase SQL editor.

-- ============================================================
-- STEP 1: Remove duplicate rows caused by the old sync bug.
-- For each item_id, keep only the row with the greatest ctid
-- (i.e. the most recently inserted row).
-- ============================================================
DELETE FROM item_prices
WHERE ctid NOT IN (
    SELECT MAX(ctid)
    FROM item_prices
    GROUP BY item_id
);

-- ============================================================
-- STEP 2: Drop the old `id`-based primary key and `id` column.
-- ============================================================
ALTER TABLE item_prices DROP CONSTRAINT IF EXISTS item_prices_pkey;
ALTER TABLE item_prices DROP COLUMN IF EXISTS id;

-- ============================================================
-- STEP 3: Make item_id the primary key.
-- This also implicitly creates a UNIQUE + NOT NULL constraint,
-- which is exactly what the upsert onConflict: "item_id" needs.
-- ============================================================
ALTER TABLE item_prices ADD PRIMARY KEY (item_id);

-- ============================================================
-- VERIFICATION
-- ============================================================
-- After running, confirm with:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'item_prices';
--
-- Expected result: item_id (uuid, NO), amount (numeric, YES), currency (text, YES)
-- No `id` column should appear.
