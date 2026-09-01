-- Calendar events + join tables (owner sync). Apply in Supabase SQL editor.
-- RLS policies for these tables already live in SUPABASE_RLS_POLICIES.sql.
-- Event invites / participants: run SUPABASE_EVENT_PARTICIPANTS.sql after this file.
--
-- If `events` already existed without newer columns, also run the ALTER block at the bottom
-- (CREATE TABLE IF NOT EXISTS does not add missing columns).

CREATE TABLE IF NOT EXISTS public.events (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    name TEXT,
    theme TEXT,
    occasion TEXT,
    notes TEXT,
    location TEXT,
    full_address TEXT,
    latitude DOUBLE PRECISION NOT NULL DEFAULT 0,
    longitude DOUBLE PRECISION NOT NULL DEFAULT 0,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    -- Legacy Core Data fields (optional; primary scheduling uses start_date / end_date)
    date TIMESTAMPTZ,
    "time" TIMESTAMPTZ,
    "timestamp" TIMESTAMPTZ,
    visibility TEXT NOT NULL DEFAULT 'private'
        CHECK (visibility IN ('private', 'friends', 'public')),
    is_soft_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS events_user_id_idx ON public.events (user_id);
CREATE INDEX IF NOT EXISTS events_user_start_date_idx ON public.events (user_id, start_date);

CREATE TABLE IF NOT EXISTS public.event_items (
    event_id UUID NOT NULL REFERENCES public.events (id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.items (id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (event_id, item_id)
);

CREATE INDEX IF NOT EXISTS event_items_item_id_idx ON public.event_items (item_id);

CREATE TABLE IF NOT EXISTS public.event_outfits (
    event_id UUID NOT NULL REFERENCES public.events (id) ON DELETE CASCADE,
    outfit_id UUID NOT NULL REFERENCES public.outfits (id) ON DELETE CASCADE,
    PRIMARY KEY (event_id, outfit_id)
);

CREATE INDEX IF NOT EXISTS event_outfits_outfit_id_idx ON public.event_outfits (outfit_id);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_outfits ENABLE ROW LEVEL SECURITY;

-- Owner-only manage (matches SUPABASE_RLS_POLICIES.sql). Re-create if missing.
DROP POLICY IF EXISTS "Users can manage own events" ON public.events;
CREATE POLICY "Users can manage own events"
ON public.events FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Owner-only manage. After SUPABASE_EVENT_PARTICIPANTS.sql, accepted guests get read + own-row write.
DROP POLICY IF EXISTS "Users can manage own event items" ON public.event_items;
DROP POLICY IF EXISTS "Event owner manages event items" ON public.event_items;
CREATE POLICY "Users can manage own event items"
ON public.event_items FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.events
        WHERE events.id = event_items.event_id
          AND events.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.events
        WHERE events.id = event_items.event_id
          AND events.user_id::text = auth.uid()::text
    )
);

DROP POLICY IF EXISTS "Users can manage own event outfits" ON public.event_outfits;
DROP POLICY IF EXISTS "Event owner manages event outfits" ON public.event_outfits;
CREATE POLICY "Users can manage own event outfits"
ON public.event_outfits FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM public.events
        WHERE events.id = event_outfits.event_id
          AND events.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.events
        WHERE events.id = event_outfits.event_id
          AND events.user_id::text = auth.uid()::text
    )
);

-- ---------------------------------------------------------------------------
-- Migrate existing `events` table (safe to re-run)
-- CREATE TABLE IF NOT EXISTS does not add columns to tables that already exist.
-- ---------------------------------------------------------------------------
ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS theme TEXT;

ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS occasion TEXT;

ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'private';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'events_visibility_check'
          AND conrelid = 'public.events'::regclass
    ) THEN
        ALTER TABLE public.events
            ADD CONSTRAINT events_visibility_check
            CHECK (visibility IN ('private', 'friends', 'public'));
    END IF;
END $$;

ALTER TABLE public.events
    ADD COLUMN IF NOT EXISTS is_soft_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.event_items
    ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;
