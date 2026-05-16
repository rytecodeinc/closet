-- Packing checklist rows (Items / To-Do segments) per wardrobe. Run in Supabase SQL editor after `wardrobes` exists.

CREATE TABLE IF NOT EXISTS public.packing_checklist_items (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    wardrobe_id uuid NOT NULL REFERENCES public.wardrobes (id) ON DELETE CASCADE,
    kind smallint NOT NULL DEFAULT 0,
    checklist_text text NOT NULL DEFAULT '',
    is_completed boolean NOT NULL DEFAULT false,
    sort_index integer NOT NULL DEFAULT 0,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS packing_checklist_items_wardrobe_kind_idx
    ON public.packing_checklist_items (wardrobe_id, kind, sort_index);

COMMENT ON TABLE public.packing_checklist_items IS 'Travel packing checklist lines; kind 0 = Items tab, 1 = To-Do.';
COMMENT ON COLUMN public.packing_checklist_items.kind IS '0 = closet physical items tab, 1 = to-do / actions tab.';

ALTER TABLE public.packing_checklist_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own packing_checklist_items" ON public.packing_checklist_items;
CREATE POLICY "Users manage own packing_checklist_items"
ON public.packing_checklist_items
FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);
