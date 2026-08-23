-- One packing checklist document per wardrobe + tab (Items / Tasks). Run after `wardrobes` exists.
-- Last-write-wins on the whole `body` jsonb blob.

CREATE TABLE IF NOT EXISTS public.packing_checklist_documents (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    wardrobe_id uuid NOT NULL REFERENCES public.wardrobes (id) ON DELETE CASCADE,
    kind smallint NOT NULL DEFAULT 0,
    body jsonb NOT NULL DEFAULT '{"blocks":[]}'::jsonb,
    created_at timestamptz,
    updated_at timestamptz,
    CONSTRAINT packing_checklist_documents_wardrobe_kind_unique UNIQUE (wardrobe_id, kind)
);

CREATE INDEX IF NOT EXISTS packing_checklist_documents_user_idx
    ON public.packing_checklist_documents (user_id);

COMMENT ON TABLE public.packing_checklist_documents IS
    'Notes-like packing checklist document per wardrobe tab; kind 0 = Items, 1 = Tasks.';
COMMENT ON COLUMN public.packing_checklist_documents.kind IS
    '0 = Items tab, 1 = Tasks tab.';
COMMENT ON COLUMN public.packing_checklist_documents.body IS
    'JSON: { "blocks": [ { "type":"section","id":"…","title":"…" } | { "type":"item","id":"…","text":"…","checked":false } ] }';

ALTER TABLE public.packing_checklist_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own packing_checklist_documents" ON public.packing_checklist_documents;
CREATE POLICY "Users manage own packing_checklist_documents"
ON public.packing_checklist_documents
FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);
