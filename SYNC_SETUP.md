# Sync Setup Guide

This guide explains how to set up item syncing and photo storage for the Closet app.

## Prerequisites

1. ✅ User authentication is working
2. ✅ Supabase project is created
3. ✅ Database tables are created (from previous SQL script)

## Step 1: Set Up Supabase Storage

### Option A: Using Supabase Dashboard (Recommended)

1. Go to your Supabase Dashboard
2. Navigate to **Storage** → **Buckets**
3. Click **New Bucket**
4. Configure:
   - **Name**: `item-photos`
   - **Public**: `false` (private bucket)
   - **File size limit**: `5242880` (5MB)
   - **Allowed MIME types**: `image/jpeg`, `image/jpg`, `image/png`, `image/webp`
5. Click **Create bucket**

### Option B: Using SQL Script

Run the SQL script in `SUPABASE_STORAGE_SETUP.sql` in your Supabase SQL Editor.

## Step 2: Set Up Storage RLS Policies

Run the RLS policies from `SUPABASE_STORAGE_SETUP.sql`:

```sql
-- Users can upload their own photos
CREATE POLICY "Users can upload own photos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'item-photos' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Users can read their own photos
CREATE POLICY "Users can read own photos"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'item-photos' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Users can update their own photos
CREATE POLICY "Users can update own photos"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'item-photos' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Users can delete their own photos
CREATE POLICY "Users can delete own photos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'item-photos' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);
```

## Step 3: Verify Storage Setup

1. In Supabase Dashboard → Storage → `item-photos` bucket
2. Check that RLS is enabled
3. Verify policies are created

## How It Works

### Photo Storage Strategy

- **Full Images**: Uploaded to Supabase Storage (`item-photos` bucket)
  - Path format: `{userId}/{itemId}/{photoId}.jpg`
  - Compressed JPEG format (max 500KB per image)
  - URL stored in `item_photos.image_url` column

- **Thumbnails**: Stored locally in Core Data
  - Kept in `Photo.thumbnailData` attribute
  - Used for fast grid view loading
  - Optional: Also stored as base64 in Supabase for quick access

### Sync Process

1. **On Login**: 
   - Existing items are attributed to the user (`userId` set)
   - Background sync starts automatically

2. **Item Sync**:
   - Uploads item metadata to `items` table
   - Uploads full photos to Supabase Storage
   - Stores photo URLs in `item_photos` table
   - Syncs relationships (colors, seasons, tags, etc.)
   - Marks items as synced (`syncedAt` timestamp)

3. **Space Efficiency**:
   - Full images: Cloud storage (Supabase Storage)
   - Thumbnails: Local Core Data (50-100KB each)
   - After successful upload, full image data can be cleared from Core Data (optional)

### Manual Sync

You can trigger manual sync from anywhere in the app:

```swift
Task {
    do {
        try await SyncService.shared.syncAllItems()
    } catch {
        print("Sync failed: \(error)")
    }
}
```

## Testing

1. **Create test items** with photos locally
2. **Log in** to your account
3. **Check sync status** - items should upload automatically
4. **Verify in Supabase**:
   - Check `items` table for your items
   - Check `item_photos` table for photo metadata
   - Check Storage bucket for uploaded images

## Troubleshooting

### Photos not uploading
- Check Storage bucket exists and is named `item-photos`
- Verify RLS policies are set correctly
- Check file size limits (5MB default)
- Verify user is authenticated

### Sync not starting
- Ensure `SyncService.setContext()` is called in `closetApp.swift`
- Check that user is authenticated before sync
- Verify network connectivity

### Storage quota exceeded
- Supabase free tier: 1GB storage
- Consider implementing image compression before upload
- Consider clearing old photos or implementing cleanup

## Next Steps

- [ ] Implement background sync on app launch (if user is authenticated)
- [ ] Add sync status indicator in UI
- [ ] Implement conflict resolution for multi-device sync
- [ ] Add download/restore functionality for synced items
- [ ] Implement incremental sync (only changed items)

