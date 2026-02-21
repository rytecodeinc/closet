# Size Independence Migration

This document explains the migration to make sizes independent of categories in Supabase.

## Overview

Previously, sizes were required to have a `category_id` (foreign key to categories table). The app has been updated so that sizes can exist independently without categories. This migration updates the Supabase schema to match this change.

## Changes Made

### 1. Database Schema Changes

Run the SQL migration script: `SUPABASE_SIZE_MIGRATION.sql`

This script:
- Drops the foreign key constraint `sizes_category_id_fkey`
- Drops the old unique constraint that included `category_id`
- Makes `category_id` nullable
- Creates a new unique constraint on `(user_id, value, scale)` to prevent duplicate sizes per user

### 2. Code Changes

#### SyncService.swift

**Updated `syncSize` method:**
- Removed the requirement for `category_id` when syncing sizes
- Made `categoryId` optional in `SyncSizeData` struct
- Sizes can now be synced even if they don't have a category

**Updated `syncItem` method:**
- Removed logic that excluded `size_id` when size didn't have a category
- Items can now always reference sizes, regardless of category

**Updated size sync logic:**
- Sizes are still synced before items (to avoid foreign key violations)
- But sizes without categories are now included in the sync

## Migration Steps

1. **Run the SQL migration script** in Supabase SQL Editor:
   ```sql
   -- See SUPABASE_SIZE_MIGRATION.sql
   ```

2. **Verify the migration**:
   - Check that `category_id` is nullable in the `sizes` table
   - Verify the new unique constraint exists: `sizes_user_id_value_scale_unique`
   - Confirm the old foreign key constraint is removed

3. **Test the sync**:
   - Sync should now work for sizes without categories
   - Items referencing sizes without categories should sync successfully

## Database Schema After Migration

```sql
CREATE TABLE sizes (
    id UUID PRIMARY KEY,
    user_id TEXT NOT NULL,
    category_id UUID NULL,  -- Now nullable, no foreign key
    value TEXT NOT NULL,
    scale TEXT,
    sort_order INTEGER,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    
    -- New unique constraint (no category_id)
    UNIQUE (user_id, value, scale)
);
```

## Notes

- Existing sizes with `category_id` will continue to work
- New sizes can be created without `category_id`
- The unique constraint ensures one size per `(user_id, value, scale)` combination
- Items can reference any size, regardless of whether it has a category

