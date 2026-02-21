-- ============================================
-- Supabase Storage Setup for Closet App
-- ============================================
-- Run this script in Supabase Dashboard → SQL Editor
-- ============================================

-- 1. Create Storage Bucket for Item Photos
-- Go to Storage → New Bucket in Supabase Dashboard
-- OR run this SQL (if bucket doesn't exist):

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'item-photos',
    'item-photos',
    false, -- Private bucket (use RLS)
    5242880, -- 5MB file size limit
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 2. Enable Row Level Security on Storage
-- NOTE: You cannot modify storage.objects policies via SQL - use Dashboard instead!
-- Go to: Storage → item-photos bucket → Policies tab

-- 3. Create RLS Policies for Storage Bucket via Dashboard
-- ============================================
-- IMPORTANT: Storage RLS policies must be created via Supabase Dashboard
-- ============================================
-- Steps:
-- 1. Go to Supabase Dashboard → Storage → item-photos bucket
-- 2. Click on "Policies" tab
-- 3. Click "New Policy"
-- 4. For each policy below, create it with the specified settings:
-- ============================================

-- Policy 1: "Users can upload own photos"
-- Type: INSERT
-- Target roles: authenticated
-- USING expression: (leave empty)
-- WITH CHECK expression:
bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text

-- Policy 2: "Users can read own photos"
-- Type: SELECT
-- Target roles: authenticated
-- USING expression:
bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
-- WITH CHECK expression: (leave empty)

-- Policy 3: "Users can update own photos"
-- Type: UPDATE
-- Target roles: authenticated
-- USING expression:
bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
-- WITH CHECK expression:
bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text

-- Policy 4: "Users can delete own photos"
-- Type: DELETE
-- Target roles: authenticated
-- USING expression:
bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
-- WITH CHECK expression: (leave empty)

-- ============================================
-- Alternative: If Dashboard doesn't work, try this SQL:
-- (Run in Supabase Dashboard → SQL Editor with "Run as service_role" if available)
-- ============================================

-- ============================================
-- Notes:
-- ============================================
-- 1. Storage paths will be: {userId}/{itemId}/{photoId}.jpg
-- 2. The first folder segment is the user ID, which RLS uses for access control
-- 3. Photos are stored as JPEG for maximum compression
-- 4. File size limit is 5MB per photo (adjust if needed)
-- 5. Bucket is private - users can only access their own photos
-- ============================================

