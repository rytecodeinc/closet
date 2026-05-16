-- Optional heading for the travel packing checklist section (shown under the Items / To-Do segment).
-- Run in Supabase SQL editor; RLS on `wardrobes` unchanged.

ALTER TABLE public.wardrobes
    ADD COLUMN IF NOT EXISTS packing_checklist_section_title text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.wardrobes.packing_checklist_section_title IS
    'Travel packing checklist section label; empty means use app default (GENERAL).';
