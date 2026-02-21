# Storage RLS Policies Setup Guide

## Problem

You cannot create Storage RLS policies via SQL in Supabase because you don't have owner permissions on the `storage.objects` table. You must use the Supabase Dashboard instead.

## Solution: Use Supabase Dashboard

### Step 1: Navigate to Storage Bucket

1. Go to your **Supabase Dashboard**
2. Click on **Storage** in the left sidebar
3. Click on the **`item-photos`** bucket (or create it if it doesn't exist)

### Step 2: Create RLS Policies

Click on the **"Policies"** tab in the bucket view.

#### Policy 1: Users can upload own photos

1. Click **"New Policy"**
2. Select **"Create a policy from scratch"** (or use template)
3. Configure:
   - **Policy name**: `Users can upload own photos`
   - **Allowed operation**: `INSERT`
   - **Target roles**: `authenticated`
   - **USING expression**: (leave empty)
   - **WITH CHECK expression**: 
     ```sql
     bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
     ```
4. Click **"Review"** then **"Save policy"**

#### Policy 2: Users can read own photos

1. Click **"New Policy"**
2. Configure:
   - **Policy name**: `Users can read own photos`
   - **Allowed operation**: `SELECT`
   - **Target roles**: `authenticated`
   - **USING expression**:
     ```sql
     bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
     ```
   - **WITH CHECK expression**: (leave empty)
3. Click **"Review"** then **"Save policy"**

#### Policy 3: Users can update own photos

1. Click **"New Policy"**
2. Configure:
   - **Policy name**: `Users can update own photos`
   - **Allowed operation**: `UPDATE`
   - **Target roles**: `authenticated`
   - **USING expression**:
     ```sql
     bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
     ```
   - **WITH CHECK expression**:
     ```sql
     bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
     ```
3. Click **"Review"** then **"Save policy"**

#### Policy 4: Users can delete own photos

1. Click **"New Policy"**
2. Configure:
   - **Policy name**: `Users can delete own photos`
   - **Allowed operation**: `DELETE`
   - **Target roles**: `authenticated`
   - **USING expression**:
     ```sql
     bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
     ```
   - **WITH CHECK expression**: (leave empty)
3. Click **"Review"** then **"Save policy"**

## How It Works

The policy expression `split_part(name, '/', 1) = auth.uid()::text` checks that:
- The file path starts with the authenticated user's ID
- Path format: `{userId}/{itemId}/{photoId}.jpg`
- Example: `979831FD-D10E-479F-A639-180339449CCA/3573FBE0-4761-4197-A98F-E72E0F756205/photo-id.jpg`

This ensures users can only access files in their own folder.

## Verification

After creating the policies:

1. **Check policies exist**: In the bucket's Policies tab, you should see all 4 policies
2. **Test upload**: Try syncing an item with photos - it should work now
3. **Check logs**: If uploads still fail, check the error message for details

## Troubleshooting

### Still getting RLS errors?

1. **Verify bucket exists**: Make sure `item-photos` bucket is created
2. **Check policy syntax**: Ensure the expression is exactly:
   ```sql
   bucket_id = 'item-photos' AND split_part(name, '/', 1) = auth.uid()::text
   ```
3. **Verify user is authenticated**: Make sure `auth.uid()` returns a valid UUID
4. **Check path format**: Ensure file paths match `userId/itemId/photoId.jpg` format

### Alternative: Use service_role key (Advanced)

If you have access to the service_role key, you can run SQL with elevated permissions, but this is **not recommended** for security reasons. The Dashboard method is the correct approach.

