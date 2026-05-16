-- Named sections within a travel packing checklist tab (Items / To-Do). Run after `wardrobes` exists.

CREATE TABLE IF NOT EXISTS public.packing_checklist_sections (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    wardrobe_id uuid NOT NULL REFERENCES public.wardrobes (id) ON DELETE CASCADE,
    kind smallint NOT NULL DEFAULT 0,
    title text NOT NULL DEFAULT '',
    sort_index integer NOT NULL DEFAULT 0,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS packing_checklist_sections_wardrobe_kind_idx
    ON public.packing_checklist_sections (wardrobe_id, kind, sort_index);

COMMENT ON TABLE public.packing_checklist_sections IS 'Checklist section headers per wardrobe tab; kind 0 = Items, 1 = To-Do.';

ALTER TABLE public.packing_checklist_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own packing_checklist_sections" ON public.packing_checklist_sections;
CREATE POLICY "Users manage own packing_checklist_sections"
ON public.packing_checklist_sections
FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Link checklist rows to a section (nullable for legacy rows).
ALTER TABLE public.packing_checklist_items
    ADD COLUMN IF NOT EXISTS section_id uuid REFERENCES public.packing_checklist_sections (id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS packing_checklist_items_section_idx
    ON public.packing_checklist_items (section_id, sort_index);
