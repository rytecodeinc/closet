-- Migration: Create notifications table for per-user, per-event in-app notifications
-- Run this in the Supabase SQL editor.

-- 1. Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,                 -- recipient of the notification
    type text NOT NULL,                    -- e.g. 'friend_request', 'friend_accepted', 'comment', etc.
    title text NOT NULL,                   -- short title for in-app display
    body text,                             -- optional longer message / context
    payload jsonb,                         -- optional extra data (e.g. related ids)
    is_read boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Optional: index for faster lookups per user and unread state
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at
    ON notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications (user_id, is_read, created_at DESC);

-- 2. Enable Row Level Security
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 3. RLS policies

-- Users can see their own notifications
DROP POLICY IF EXISTS "Users can select own notifications" ON notifications;
CREATE POLICY "Users can select own notifications"
ON notifications FOR SELECT
USING (user_id::text = auth.uid()::text);

-- Users can insert notifications for themselves (optional; you may also choose to
-- insert notifications only from backend service roles).
DROP POLICY IF EXISTS "Users can insert own notifications" ON notifications;
CREATE POLICY "Users can insert own notifications"
ON notifications FOR INSERT
WITH CHECK (user_id::text = auth.uid()::text);

-- Users can update (e.g. mark as read) their own notifications
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
CREATE POLICY "Users can update own notifications"
ON notifications FOR UPDATE
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Users cannot delete notifications by default (keep history).
-- If you want to allow deletion, uncomment this:
-- DROP POLICY IF EXISTS "Users can delete own notifications" ON notifications;
-- CREATE POLICY "Users can delete own notifications"
-- ON notifications FOR DELETE
-- USING (user_id::text = auth.uid()::text);

