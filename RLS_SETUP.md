# Row Level Security (RLS) Setup Guide

## Problem

If you're seeing errors like:
```
⚠️ Sync failed after login: new row violates row-level security policy
```

This means Row Level Security (RLS) is enabled on your Supabase tables, but the policies haven't been created yet. RLS policies control who can access what data.

## Solution

Run the SQL script `SUPABASE_RLS_POLICIES.sql` in your Supabase SQL Editor.

### Steps:

1. **Open Supabase Dashboard**
   - Go to your project
   - Navigate to **SQL Editor**

2. **Run the RLS Policies Script**
   - Open `SUPABASE_RLS_POLICIES.sql`
   - Copy the entire contents
   - Paste into the SQL Editor
   - Click **Run** or press `Cmd+Enter` (Mac) / `Ctrl+Enter` (Windows)

3. **Verify Policies Are Created**
   - Run this query to see all policies:
   ```sql
   SELECT tablename, policyname, cmd 
   FROM pg_policies 
   WHERE schemaname = 'public' 
   ORDER BY tablename;
   ```
   - You should see policies for all tables (items, brands, categories, etc.)

## How RLS Policies Work

The policies ensure that:
- Users can only **SELECT** (read) their own data
- Users can only **INSERT** (create) data with their own `user_id`
- Users can only **UPDATE** (modify) their own data
- Users can only **DELETE** (remove) their own data

All policies check: `user_id = auth.uid()::text`

This means:
- When you're logged in, `auth.uid()` returns your user ID
- The policy compares your `user_id` column with your authenticated user ID
- Only rows where they match are accessible

## Troubleshooting

### Issue: Still getting RLS violations after running the script

1. **Check if RLS is enabled:**
   ```sql
   SELECT tablename, rowsecurity 
   FROM pg_tables 
   WHERE schemaname = 'public' 
   AND tablename = 'items';
   ```
   - `rowsecurity = true` means RLS is enabled

2. **Check if policies exist:**
   ```sql
   SELECT * FROM pg_policies 
   WHERE tablename = 'items';
   ```
   - Should return 4 policies (SELECT, INSERT, UPDATE, DELETE)

3. **Check your user ID format:**
   ```sql
   SELECT auth.uid()::text as current_user_id;
   ```
   - Compare this with the `user_id` values in your tables
   - They should match exactly (case-sensitive)

4. **Test with a simple query:**
   ```sql
   -- This should only return your own items
   SELECT id, name, user_id FROM items;
   ```

### Issue: UUID format mismatch

If `user_id` is stored differently than `auth.uid()`, you might need to adjust the policies:

```sql
-- Alternative policy using case-insensitive comparison
CREATE POLICY "Users can select own items"
ON items FOR SELECT
USING (LOWER(user_id) = LOWER(auth.uid()::text));
```

However, this shouldn't be necessary if you're using `uuidString` consistently.

## What Gets Protected

All tables with RLS enabled:
- ✅ `items` - Your closet items
- ✅ `brands`, `categories`, `colors`, etc. - Reference data
- ✅ `item_photos`, `item_prices`, `item_links` - Child tables
- ✅ `item_colors`, `item_seasons`, etc. - Junction tables
- ✅ `outfits`, `events`, `wardrobes` - Other main entities
- ✅ `user_profiles` - User profile data

## Security Note

These policies ensure that:
- Users cannot see other users' data
- Users cannot modify other users' data
- Users cannot delete other users' data
- Each user's data is completely isolated

This is critical for a multi-user application!

