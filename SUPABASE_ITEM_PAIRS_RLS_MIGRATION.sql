-- Migration: Add RLS policy for item_pairs table
-- Run this in the Supabase SQL editor.
--
-- Background: item_pairs had RLS enabled but no permissive policy, which caused:
--   - SELECT to silently return 0 rows (blocking pair reads)
--   - INSERT/DELETE to fail with 42501 (row-level security violation)
-- This prevented pair sync from working and made existing pairs invisible to the app.

-- Enable RLS (idempotent — safe to run even if already enabled)
ALTER TABLE item_pairs ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to fully manage pairs they own.
-- Ownership is determined by joining item_pairs.item_id → items.id and checking user_id.
-- Pairs are stored bidirectionally (A→B and B→A), and the row whose item_id belongs to
-- the current user is the one this policy governs.
DROP POLICY IF EXISTS "Users can manage own item pairs" ON item_pairs;
CREATE POLICY "Users can manage own item pairs"
ON item_pairs FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items
        WHERE items.id = item_pairs.item_id
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items
        WHERE items.id = item_pairs.item_id
        AND items.user_id::text = auth.uid()::text
    )
);

-- Verify the policy was created:
-- SELECT tablename, policyname, cmd FROM pg_policies
-- WHERE schemaname = 'public' AND tablename = 'item_pairs';
