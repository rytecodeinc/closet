-- Migration: Replace outfits.category (text) with outfit_categories reference table
-- Run in Supabase SQL editor after backups.
--
-- Matches app sync:
--   outfit_categories: id, user_id, name
--   outfits.category_id → outfit_categories.id

-- ============================================================
-- STEP 1: Create outfit_categories table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.outfit_categories (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    name text NOT NULL,
    CONSTRAINT outfit_categories_name_not_blank CHECK (char_length(trim(name)) > 0)
);

-- Case-insensitive unique name per user (matches app fetchOrCreateOutfitCategory)
CREATE UNIQUE INDEX IF NOT EXISTS outfit_categories_user_name_lower_idx
    ON public.outfit_categories (user_id, lower(trim(name)));

CREATE INDEX IF NOT EXISTS outfit_categories_user_id_idx
    ON public.outfit_categories (user_id);

COMMENT ON TABLE public.outfit_categories IS 'User-defined outfit categories (separate from item categories).';

-- ============================================================
-- STEP 2: Backfill from legacy outfits.category text column
-- (Skip if column does not exist on a fresh schema.)
-- ============================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'outfits'
          AND column_name = 'category'
    ) THEN
        INSERT INTO public.outfit_categories (id, user_id, name)
        SELECT
            gen_random_uuid(),
            grouped.user_id,
            grouped.canonical_name
        FROM (
            SELECT
                o.user_id,
                lower(trim(o.category)) AS name_key,
                (array_agg(trim(o.category) ORDER BY trim(o.category)))[1] AS canonical_name
            FROM public.outfits o
            WHERE o.category IS NOT NULL
              AND trim(o.category) <> ''
            GROUP BY o.user_id, lower(trim(o.category))
        ) grouped
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.outfit_categories oc
            WHERE oc.user_id = grouped.user_id
              AND lower(trim(oc.name)) = grouped.name_key
        );
    END IF;
END $$;

-- ============================================================
-- STEP 3: Add category_id FK on outfits
-- ============================================================
ALTER TABLE public.outfits
    ADD COLUMN IF NOT EXISTS category_id uuid;

ALTER TABLE public.outfits
    DROP CONSTRAINT IF EXISTS outfits_category_id_fkey;

ALTER TABLE public.outfits
    ADD CONSTRAINT outfits_category_id_fkey
    FOREIGN KEY (category_id)
    REFERENCES public.outfit_categories (id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS outfits_category_id_idx
    ON public.outfits (category_id);

-- Link existing rows to backfilled categories
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'outfits'
          AND column_name = 'category'
    ) THEN
        UPDATE public.outfits o
        SET category_id = oc.id
        FROM public.outfit_categories oc
        WHERE o.category_id IS NULL
          AND o.category IS NOT NULL
          AND trim(o.category) <> ''
          AND o.user_id = oc.user_id
          AND lower(trim(o.category)) = lower(trim(oc.name));
    END IF;
END $$;

-- ============================================================
-- STEP 4: Drop legacy text column
-- ============================================================
ALTER TABLE public.outfits
    DROP COLUMN IF EXISTS category;

-- ============================================================
-- STEP 5: Row Level Security
-- ============================================================
ALTER TABLE public.outfit_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own outfit categories" ON public.outfit_categories;
CREATE POLICY "Users can manage own outfit categories"
ON public.outfit_categories
FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- ============================================================
-- VERIFICATION
-- ============================================================
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name IN ('outfit_categories', 'outfits')
--   AND column_name IN ('id', 'user_id', 'name', 'category', 'category_id')
-- ORDER BY table_name, column_name;
--
-- Expected:
--   outfit_categories: id, user_id, name
--   outfits: category_id (nullable uuid), no category text column
