-- Migration: Create friendships table for user connections (friends)
-- Run this in the Supabase SQL editor.

CREATE TABLE IF NOT EXISTS friendships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,          -- requester
    friend_user_id uuid NOT NULL,   -- recipient
    status text NOT NULL DEFAULT 'pending', -- 'pending', 'accepted', 'declined', 'blocked'
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Ensure a unique friendship per pair/direction (optional; you can also enforce symmetry later)
CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_user_friend_unique
    ON friendships (user_id, friend_user_id);

-- Basic index for querying friendships involving a user
CREATE INDEX IF NOT EXISTS idx_friendships_friend_user
    ON friendships (friend_user_id);

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- Allow users to see friendships where they are either side (requester or recipient)
DROP POLICY IF EXISTS "Users can select own friendships" ON friendships;
CREATE POLICY "Users can select own friendships"
ON friendships FOR SELECT
USING (
    user_id::text = auth.uid()::text
    OR friend_user_id::text = auth.uid()::text
);

-- Allow users to create friendships where they are the requester
DROP POLICY IF EXISTS "Users can insert own friendships" ON friendships;
CREATE POLICY "Users can insert own friendships"
ON friendships FOR INSERT
WITH CHECK (user_id::text = auth.uid()::text);

-- Allow users to update friendships they are part of (used for accept/decline)
DROP POLICY IF EXISTS "Users can update own friendships" ON friendships;
CREATE POLICY "Users can update own friendships"
ON friendships FOR UPDATE
USING (
    user_id::text = auth.uid()::text
    OR friend_user_id::text = auth.uid()::text
)
WITH CHECK (
    user_id::text = auth.uid()::text
    OR friend_user_id::text = auth.uid()::text
);

