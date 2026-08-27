-- Event participants: invites, host row, preview-for-pending, accepted attendee access.
-- Requires: events, event_items, event_outfits, friendships, user_profiles, notifications.
-- Run in Supabase SQL Editor after SUPABASE_EVENTS.sql.
--
-- Conventions:
--   events.user_id = owner (sync + invite authority). Host is also an event_participants row
--   (status=accepted, role=host) for participant lists.
--   Pending invitees use get_event_invite_preview (Option B) — no direct SELECT on events.
--   Accepted invitees SELECT events + read all joins; write only their own event_items/event_outfits.
--   Declined/removed rows lose all event access.
--
-- TODO (ownership transfer): update events.user_id AND reassign host row (role=host) explicitly;
--   decide whether former owner becomes accepted guest, is removed, or keeps co-host role;
--   handle host leaving without deleting the event.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.event_participants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES public.events (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    invited_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'removed')),
    role text NOT NULL DEFAULT 'guest'
        CHECK (role IN ('host', 'guest')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT event_participants_not_self_invite CHECK (user_id <> invited_by OR role = 'host')
);

CREATE UNIQUE INDEX IF NOT EXISTS event_participants_event_user_unique
    ON public.event_participants (event_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS event_participants_one_host_per_event
    ON public.event_participants (event_id)
    WHERE role = 'host';

CREATE INDEX IF NOT EXISTS event_participants_user_status_idx
    ON public.event_participants (user_id, status);

CREATE INDEX IF NOT EXISTS event_participants_event_status_idx
    ON public.event_participants (event_id, status);

COMMENT ON TABLE public.event_participants IS
    'Event roster: host row (accepted) + invited guests. Owner remains events.user_id.';

-- ---------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER for consistent checks inside RPCs / policies)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_event_owner(p_event_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.events e
        WHERE e.id = p_event_id
          AND e.user_id = auth.uid()
          AND COALESCE(e.is_soft_deleted, false) = false
    );
$$;

CREATE OR REPLACE FUNCTION public.is_accepted_event_participant(p_event_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.user_id = auth.uid()
          AND ep.status = 'accepted'
    );
$$;

CREATE OR REPLACE FUNCTION public.users_are_accepted_friends(p_user_a uuid, p_user_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
              (f.user_id = p_user_a AND f.friend_user_id = p_user_b)
              OR (f.user_id = p_user_b AND f.friend_user_id = p_user_a)
          )
    );
$$;

REVOKE ALL ON FUNCTION public.is_event_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_accepted_event_participant(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.users_are_accepted_friends(uuid, uuid) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Host row on event create
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.seed_event_host_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.event_participants (event_id, user_id, invited_by, status, role)
    VALUES (NEW.id, NEW.user_id, NEW.user_id, 'accepted', 'host')
    ON CONFLICT (event_id, user_id) DO UPDATE
        SET status = 'accepted',
            role = 'host',
            updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_seed_host_participant ON public.events;
CREATE TRIGGER events_seed_host_participant
    AFTER INSERT ON public.events
    FOR EACH ROW
    EXECUTE FUNCTION public.seed_event_host_participant();

-- Backfill host rows for events created before this migration.
INSERT INTO public.event_participants (event_id, user_id, invited_by, status, role)
SELECT e.id, e.user_id, e.user_id, 'accepted', 'host'
FROM public.events e
WHERE COALESCE(e.is_soft_deleted, false) = false
  AND NOT EXISTS (
      SELECT 1
      FROM public.event_participants ep
      WHERE ep.event_id = e.id
        AND ep.role = 'host'
  )
ON CONFLICT (event_id, user_id) DO UPDATE
    SET status = 'accepted',
        role = 'host',
        updated_at = now();

-- ---------------------------------------------------------------------------
-- event_participants RLS (reads only; mutations via RPCs)
-- ---------------------------------------------------------------------------

ALTER TABLE public.event_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read relevant event participants" ON public.event_participants;
CREATE POLICY "Users read relevant event participants"
ON public.event_participants FOR SELECT
USING (
    user_id = auth.uid()
    OR public.is_event_owner(event_id)
    OR public.is_accepted_event_participant(event_id)
);

-- ---------------------------------------------------------------------------
-- events: accepted participants may read full event (pending uses preview RPC)
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Accepted participants can read events" ON public.events;
CREATE POLICY "Accepted participants can read events"
ON public.events FOR SELECT
USING (public.is_accepted_event_participant(id));

-- Owner manage policy remains in SUPABASE_EVENTS.sql ("Users can manage own events").

-- ---------------------------------------------------------------------------
-- event_items / event_outfits: owner full manage; accepted guests own rows only
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Users can manage own event items" ON public.event_items;
CREATE POLICY "Event owner manages event items"
ON public.event_items FOR ALL
USING (public.is_event_owner(event_id))
WITH CHECK (public.is_event_owner(event_id));

DROP POLICY IF EXISTS "Accepted participants read event items" ON public.event_items;
CREATE POLICY "Accepted participants read event items"
ON public.event_items FOR SELECT
USING (public.is_accepted_event_participant(event_id));

DROP POLICY IF EXISTS "Accepted participants manage own event items" ON public.event_items;
CREATE POLICY "Accepted participants insert own event items"
ON public.event_items FOR INSERT
WITH CHECK (
    public.is_accepted_event_participant(event_id)
    AND EXISTS (
        SELECT 1
        FROM public.items i
        WHERE i.id = event_items.item_id
          AND i.user_id = auth.uid()
    )
);

CREATE POLICY "Accepted participants delete own event items"
ON public.event_items FOR DELETE
USING (
    public.is_accepted_event_participant(event_id)
    AND EXISTS (
        SELECT 1
        FROM public.items i
        WHERE i.id = event_items.item_id
          AND i.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Users can manage own event outfits" ON public.event_outfits;
CREATE POLICY "Event owner manages event outfits"
ON public.event_outfits FOR ALL
USING (public.is_event_owner(event_id))
WITH CHECK (public.is_event_owner(event_id));

DROP POLICY IF EXISTS "Accepted participants read event outfits" ON public.event_outfits;
CREATE POLICY "Accepted participants read event outfits"
ON public.event_outfits FOR SELECT
USING (public.is_accepted_event_participant(event_id));

DROP POLICY IF EXISTS "Accepted participants manage own event outfits" ON public.event_outfits;
CREATE POLICY "Accepted participants insert own event outfits"
ON public.event_outfits FOR INSERT
WITH CHECK (
    public.is_accepted_event_participant(event_id)
    AND EXISTS (
        SELECT 1
        FROM public.outfits o
        WHERE o.id = event_outfits.outfit_id
          AND o.user_id = auth.uid()
    )
);

CREATE POLICY "Accepted participants delete own event outfits"
ON public.event_outfits FOR DELETE
USING (
    public.is_accepted_event_participant(event_id)
    AND EXISTS (
        SELECT 1
        FROM public.outfits o
        WHERE o.id = event_outfits.outfit_id
          AND o.user_id = auth.uid()
    )
);

-- ---------------------------------------------------------------------------
-- RPC: pending invite preview (Option B)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_event_invite_preview(uuid);

CREATE OR REPLACE FUNCTION public.get_event_invite_preview(p_event_id uuid)
RETURNS TABLE (
    event_id uuid,
    name text,
    theme text,
    location text,
    start_date timestamptz,
    end_date timestamptz,
    host_user_id uuid,
    host_username text,
    host_display_name text,
    host_avatar_url text,
    participant_status text,
    invited_by uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_event_id IS NULL THEN
        RAISE EXCEPTION 'Missing event id';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.event_participants ep
        INNER JOIN public.events e ON e.id = ep.event_id
        WHERE ep.event_id = p_event_id
          AND ep.user_id = v_uid
          AND ep.status = 'pending'
          AND COALESCE(e.is_soft_deleted, false) = false
    ) THEN
        RAISE EXCEPTION 'Invite preview not available';
    END IF;

    RETURN QUERY
    SELECT
        e.id,
        e.name,
        e.theme,
        e.location,
        e.start_date,
        e.end_date,
        up.user_id,
        up.username,
        up.display_name,
        up.avatar_url,
        ep.status,
        ep.invited_by
    FROM public.event_participants ep
    INNER JOIN public.events e ON e.id = ep.event_id
    INNER JOIN public.user_profiles up ON up.user_id = e.user_id
    WHERE ep.event_id = p_event_id
      AND ep.user_id = v_uid
      AND ep.status = 'pending'
      AND COALESCE(e.is_soft_deleted, false) = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_event_invite_preview(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: list participants (owner or accepted attendee)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_event_participants(uuid);

CREATE OR REPLACE FUNCTION public.get_event_participants(p_event_id uuid)
RETURNS TABLE (
    participant_id uuid,
    user_id uuid,
    username text,
    display_name text,
    avatar_url text,
    status text,
    role text,
    invited_by uuid,
    created_at timestamptz,
    updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT (
        public.is_event_owner(p_event_id)
        OR public.is_accepted_event_participant(p_event_id)
    ) THEN
        RAISE EXCEPTION 'Not allowed';
    END IF;

    RETURN QUERY
    SELECT
        ep.id,
        ep.user_id,
        up.username,
        up.display_name,
        up.avatar_url,
        ep.status,
        ep.role,
        ep.invited_by,
        ep.created_at,
        ep.updated_at
    FROM public.event_participants ep
    INNER JOIN public.user_profiles up ON up.user_id = ep.user_id
    WHERE ep.event_id = p_event_id
      AND ep.status IN ('pending', 'accepted')
    ORDER BY
        CASE WHEN ep.role = 'host' THEN 0 ELSE 1 END,
        ep.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_event_participants(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: invite friend to event (owner only)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.invite_to_event(uuid, uuid);

CREATE OR REPLACE FUNCTION public.invite_to_event(
    p_event_id uuid,
    p_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_host uuid := auth.uid();
    v_participant_id uuid;
    v_event_name text;
    v_host_username text;
    v_host_display text;
    v_label text;
BEGIN
    IF v_host IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Missing event or user id';
    END IF;

    IF p_user_id = v_host THEN
        RAISE EXCEPTION 'Cannot invite yourself';
    END IF;

    IF NOT public.is_event_owner(p_event_id) THEN
        RAISE EXCEPTION 'Only the event owner can invite';
    END IF;

    IF NOT public.users_are_accepted_friends(v_host, p_user_id) THEN
        RAISE EXCEPTION 'User is not an accepted friend';
    END IF;

    SELECT e.name INTO v_event_name
    FROM public.events e
    WHERE e.id = p_event_id
      AND COALESCE(e.is_soft_deleted, false) = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.user_id = p_user_id
          AND ep.role = 'host'
    ) THEN
        RAISE EXCEPTION 'Cannot invite the event host';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.user_id = p_user_id
          AND ep.status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'User is already a participant';
    END IF;

    INSERT INTO public.event_participants (event_id, user_id, invited_by, status, role)
    VALUES (p_event_id, p_user_id, v_host, 'pending', 'guest')
    ON CONFLICT (event_id, user_id) DO UPDATE
        SET status = 'pending',
            invited_by = v_host,
            role = 'guest',
            updated_at = now()
    WHERE public.event_participants.role = 'guest'
      AND public.event_participants.status IN ('pending', 'declined', 'removed')
    RETURNING id INTO v_participant_id;

    IF v_participant_id IS NULL THEN
        SELECT ep.id INTO v_participant_id
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.user_id = p_user_id
          AND ep.status = 'pending';

        IF v_participant_id IS NULL THEN
            RAISE EXCEPTION 'Could not create invite';
        END IF;
    END IF;

    SELECT up.username, up.display_name
    INTO v_host_username, v_host_display
    FROM public.user_profiles up
    WHERE up.user_id = v_host;

    v_label := coalesce(
        nullif(trim(v_host_display), ''),
        nullif(trim(v_host_username), ''),
        'Someone'
    );

    -- Idempotent: one unread invite notification per participant row.
    IF NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n.user_id = p_user_id
          AND n.type = 'event_invite'
          AND (n.payload->>'participant_id') = v_participant_id::text
          AND n.is_read = false
    ) THEN
        INSERT INTO public.notifications (user_id, type, title, body, payload)
        VALUES (
            p_user_id,
            'event_invite',
            v_label || ' invited you to an event',
            nullif(trim(coalesce(v_event_name, '')), ''),
            jsonb_build_object(
                'event_id', p_event_id::text,
                'participant_id', v_participant_id::text,
                'from_user_id', v_host::text,
                'from_username', v_host_username
            )
        );
    END IF;

    RETURN v_participant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.invite_to_event(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: accept / decline pending invite
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.respond_to_event_invite(uuid, text);

CREATE OR REPLACE FUNCTION public.respond_to_event_invite(
    p_event_id uuid,
    p_accept text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_accept boolean := coalesce(nullif(trim(p_accept), ''), 'false')::boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE public.event_participants ep
    SET
        status = CASE WHEN v_accept THEN 'accepted' ELSE 'declined' END,
        updated_at = now()
    WHERE ep.event_id = p_event_id
      AND ep.user_id = auth.uid()
      AND ep.status = 'pending'
      AND ep.role = 'guest';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or not actionable';
    END IF;

    -- Mark matching invite notifications read after respond.
    UPDATE public.notifications n
    SET is_read = true
    WHERE n.user_id = auth.uid()
      AND n.type = 'event_invite'
      AND (n.payload->>'event_id') = p_event_id::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_event_invite(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: owner removes a guest (soft status)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.remove_event_participant(uuid, uuid);

CREATE OR REPLACE FUNCTION public.remove_event_participant(
    p_event_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT public.is_event_owner(p_event_id) THEN
        RAISE EXCEPTION 'Only the event owner can remove participants';
    END IF;

    UPDATE public.event_participants ep
    SET status = 'removed', updated_at = now()
    WHERE ep.event_id = p_event_id
      AND ep.user_id = p_user_id
      AND ep.role = 'guest'
      AND ep.status IN ('pending', 'accepted');

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Participant not found or not removable';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_event_participant(uuid, uuid) TO authenticated;
