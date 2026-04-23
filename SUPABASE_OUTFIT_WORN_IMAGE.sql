-- Optional: add column for outfit "worn" photo URL (R2). Run in Supabase SQL editor if sync fails after app update.
ALTER TABLE outfits ADD COLUMN IF NOT EXISTS worn_image_url text;
