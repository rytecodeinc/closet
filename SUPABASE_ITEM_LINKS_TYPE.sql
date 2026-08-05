-- Item link type for affiliate / purchase / reference classification.
-- Run in Supabase SQL Editor.

ALTER TABLE public.item_links
  ADD COLUMN IF NOT EXISTS type text;

COMMENT ON COLUMN public.item_links.type IS
  'Link classification: affiliate, purchase, or reference. Untyped rows are treated as purchase.';

UPDATE public.item_links
SET type = 'purchase'
WHERE type IS NULL OR btrim(type) = '';

ALTER TABLE public.item_links
  ALTER COLUMN type SET DEFAULT 'purchase';

ALTER TABLE public.item_links
  DROP CONSTRAINT IF EXISTS item_links_type_check;

ALTER TABLE public.item_links
  ADD CONSTRAINT item_links_type_check
  CHECK (type IN ('affiliate', 'purchase', 'reference'));

ALTER TABLE public.item_links
  ALTER COLUMN type SET NOT NULL;
