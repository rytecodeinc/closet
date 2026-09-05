-- Event invitee flow: richer preview, roster for pending, wardrobe thumbs,
-- invite copy/cap/visibility, host accept/decline notify, notification cleanup.
-- Run after SUPABASE_EVENT_PARTICIPANTS.sql (and SUPABASE_EVENTS.sql).

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_pending_event_invitee(p_event_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.event_participants ep
        INNER JOIN public.events e ON e.id = ep.event_id
        WHERE ep.event_id = p_event_id
          AND ep.user_id = auth.uid()
          AND ep.status = 'pending'
          AND ep.role = 'guest'
          AND COALESCE(e.is_soft_deleted, false) = false
    );
$$;

REVOKE ALL ON FUNCTION public.is_pending_event_invitee(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_pending_event_invitee(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.event_active_participant_count(p_event_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*)::integer
    FROM public.event_participants ep
    WHERE ep.event_id = p_event_id
      AND ep.status IN ('pending', 'accepted');
$$;

REVOKE ALL ON FUNCTION public.event_active_participant_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.event_active_participant_count(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Expanded pending invite preview
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_event_invite_preview(uuid);

CREATE OR REPLACE FUNCTION public.get_event_invite_preview(p_event_id uuid)
RETURNS TABLE (
    event_id uuid,
    name text,
    theme text,
    occasion text,
    notes text,
    location text,
    full_address text,
    latitude double precision,
    longitude double precision,
    start_date timestamptz,
    end_date timestamptz,
    visibility text,
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

    IF NOT public.is_pending_event_invitee(p_event_id) THEN
        RAISE EXCEPTION 'Invite preview not available';
    END IF;

    RETURN QUERY
    SELECT
        e.id,
        e.name,
        e.theme,
        e.occasion,
        e.notes,
        e.location,
        e.full_address,
        e.latitude,
        e.longitude,
        e.start_date,
        e.end_date,
        e.visibility,
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
-- Participants: owner, accepted guest, OR pending invitee
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
        OR public.is_pending_event_invitee(p_event_id)
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
-- Host wardrobe thumbs for pending invitee (read-only preview)
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_event_invite_wardrobe(uuid);

CREATE OR REPLACE FUNCTION public.get_event_invite_wardrobe(p_event_id uuid)
RETURNS TABLE (
    entry_kind text,
    entry_id uuid,
    image_url text,
    owner_user_id uuid,
    sort_order integer
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
        public.is_pending_event_invitee(p_event_id)
        OR public.is_accepted_event_participant(p_event_id)
        OR public.is_event_owner(p_event_id)
    ) THEN
        RAISE EXCEPTION 'Not allowed';
    END IF;

    RETURN QUERY
    SELECT * FROM (
        SELECT
            'item'::text AS entry_kind,
            i.id AS entry_id,
            COALESCE(
                (
                    SELECT COALESCE(p.thumbnail_url, p.image_url)
                    FROM public.item_photos p
                    WHERE p.item_id = i.id
                      AND COALESCE(p.is_primary, false) = true
                    ORDER BY p.created_at NULLS LAST
                    LIMIT 1
                ),
                (
                    SELECT COALESCE(p.thumbnail_url, p.image_url)
                    FROM public.item_photos p
                    WHERE p.item_id = i.id
                    ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
                    LIMIT 1
                )
            ) AS image_url,
            i.user_id AS owner_user_id,
            COALESCE(ei.sort_order, 0) AS sort_order
        FROM public.event_items ei
        INNER JOIN public.items i ON i.id = ei.item_id
        INNER JOIN public.events e ON e.id = ei.event_id
        WHERE ei.event_id = p_event_id
          AND i.user_id = e.user_id
          AND COALESCE(i.is_soft_deleted, false) = false
          AND COALESCE(i.is_draft, false) = false

        UNION ALL

        SELECT
            'outfit'::text,
            o.id,
            o.image_url,
            o.user_id,
            0
        FROM public.event_outfits eo
        INNER JOIN public.outfits o ON o.id = eo.outfit_id
        INNER JOIN public.events e ON e.id = eo.event_id
        WHERE eo.event_id = p_event_id
          AND o.user_id = e.user_id
          AND COALESCE(o.is_soft_deleted, false) = false
          AND COALESCE(o.is_draft, false) = false
    ) wardrobe
    ORDER BY wardrobe.sort_order ASC, wardrobe.entry_kind ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_event_invite_wardrobe(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Accepted events for calendar materialize
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.get_my_accepted_events();

CREATE OR REPLACE FUNCTION public.get_my_accepted_events()
RETURNS SETOF public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT e.*
    FROM public.events e
    INNER JOIN public.event_participants ep ON ep.event_id = e.id
    WHERE ep.user_id = auth.uid()
      AND ep.status = 'accepted'
      AND ep.role = 'guest'
      AND COALESCE(e.is_soft_deleted, false) = false
    ORDER BY e.start_date NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_accepted_events() TO authenticated;

-- ---------------------------------------------------------------------------
-- Invite: cap 4, force friends visibility, notification copy
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
    v_start timestamptz;
    v_visibility text;
    v_host_username text;
    v_host_display text;
    v_label text;
    v_date_label text;
    v_title text;
    v_active_count integer;
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

    SELECT e.name, e.start_date, e.visibility
    INTO v_event_name, v_start, v_visibility
    FROM public.events e
    WHERE e.id = p_event_id
      AND COALESCE(e.is_soft_deleted, false) = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found';
    END IF;

    -- Visibility stays as set by the host (private invites are allowed).
    -- private  = host event stays off guest profiles
    -- friends  = host event visible on host profile to host's friends and friends of guests
    -- public   = broader profile visibility (unchanged)

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

    -- Cap: host + guests with pending/accepted ≤ 4.
    -- Re-inviting an existing pending row does not increase count.
    IF NOT EXISTS (
        SELECT 1
        FROM public.event_participants ep
        WHERE ep.event_id = p_event_id
          AND ep.user_id = p_user_id
          AND ep.status IN ('pending', 'accepted')
    ) THEN
        v_active_count := public.event_active_participant_count(p_event_id);
        IF v_active_count >= 4 THEN
            RAISE EXCEPTION 'Event is full (maximum 4 participants)';
        END IF;
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

    v_date_label := CASE
        WHEN v_start IS NULL THEN NULL
        ELSE to_char(v_start AT TIME ZONE 'UTC', 'Dy, Mon FMDD')
    END;

    v_title := v_label
        || ' has sent you an invitation to '
        || coalesce(nullif(trim(v_event_name), ''), 'an event')
        || CASE
            WHEN v_date_label IS NULL THEN ''
            ELSE ' on ' || v_date_label
           END;

    -- Replace prior unread invite for this participant; keep one actionable row.
    DELETE FROM public.notifications n
    WHERE n.user_id = p_user_id
      AND n.type = 'event_invite'
      AND (n.payload->>'participant_id') = v_participant_id::text
      AND n.is_read = false;

    INSERT INTO public.notifications (user_id, type, title, body, payload)
    VALUES (
        p_user_id,
        'event_invite',
        v_title,
        nullif(trim(coalesce(v_event_name, '')), ''),
        jsonb_build_object(
            'event_id', p_event_id::text,
            'participant_id', v_participant_id::text,
            'from_user_id', v_host::text,
            'from_username', v_host_username,
            'event_name', coalesce(v_event_name, ''),
            'event_date_label', coalesce(v_date_label, ''),
            'event_visibility', v_visibility
        )
    );

    RETURN v_participant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.invite_to_event(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Respond: notify host; mark invite notifications read (keep row for history)
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
    v_uid uuid := auth.uid();
    v_accept boolean := coalesce(nullif(trim(p_accept), ''), 'false')::boolean;
    v_host uuid;
    v_event_name text;
    v_guest_username text;
    v_guest_display text;
    v_label text;
    v_title text;
    v_type text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE public.event_participants ep
    SET
        status = CASE WHEN v_accept THEN 'accepted' ELSE 'declined' END,
        updated_at = now()
    WHERE ep.event_id = p_event_id
      AND ep.user_id = v_uid
      AND ep.status = 'pending'
      AND ep.role = 'guest';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or not actionable';
    END IF;

    UPDATE public.notifications n
    SET is_read = true
    WHERE n.user_id = v_uid
      AND n.type = 'event_invite'
      AND (n.payload->>'event_id') = p_event_id::text;

    -- Invitee no longer needs actionable invite rows after respond.
    DELETE FROM public.notifications n
    WHERE n.user_id = v_uid
      AND n.type = 'event_invite'
      AND (n.payload->>'event_id') = p_event_id::text;

    SELECT e.user_id, e.name
    INTO v_host, v_event_name
    FROM public.events e
    WHERE e.id = p_event_id
      AND COALESCE(e.is_soft_deleted, false) = false;

    IF v_host IS NULL OR v_host = v_uid THEN
        RETURN;
    END IF;

    SELECT up.username, up.display_name
    INTO v_guest_username, v_guest_display
    FROM public.user_profiles up
    WHERE up.user_id = v_uid;

    v_label := coalesce(
        nullif(trim(v_guest_display), ''),
        nullif(trim(v_guest_username), ''),
        'Someone'
    );

    IF v_accept THEN
        v_type := 'event_invite_accepted';
        v_title := v_label
            || ' accepted your invitation to '
            || coalesce(nullif(trim(v_event_name), ''), 'an event');
    ELSE
        v_type := 'event_invite_declined';
        v_title := v_label
            || ' declined your invitation to '
            || coalesce(nullif(trim(v_event_name), ''), 'an event');
    END IF;

    INSERT INTO public.notifications (user_id, type, title, body, payload)
    VALUES (
        v_host,
        v_type,
        v_title,
        nullif(trim(coalesce(v_event_name, '')), ''),
        jsonb_build_object(
            'event_id', p_event_id::text,
            'from_user_id', v_uid::text,
            'from_username', v_guest_username,
            'event_name', coalesce(v_event_name, ''),
            'accepted', CASE WHEN v_accept THEN 'true' ELSE 'false' END
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_event_invite(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Remove guest: delete invite notifications
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

    DELETE FROM public.notifications n
    WHERE n.user_id = p_user_id
      AND n.type = 'event_invite'
      AND (n.payload->>'event_id') = p_event_id::text;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_event_participant(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Soft-delete / hard-delete event → wipe invite notifications for that event
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cleanup_event_invite_notifications()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_id uuid := COALESCE(NEW.id, OLD.id);
BEGIN
    IF TG_OP = 'UPDATE'
       AND COALESCE(NEW.is_soft_deleted, false) = true
       AND COALESCE(OLD.is_soft_deleted, false) = false THEN
        DELETE FROM public.notifications n
        WHERE n.type IN ('event_invite', 'event_invite_accepted', 'event_invite_declined')
          AND (n.payload->>'event_id') = v_event_id::text;
    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM public.notifications n
        WHERE n.type IN ('event_invite', 'event_invite_accepted', 'event_invite_declined')
          AND (n.payload->>'event_id') = v_event_id::text;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS events_cleanup_invite_notifications ON public.events;
CREATE TRIGGER events_cleanup_invite_notifications
    AFTER UPDATE OR DELETE ON public.events
    FOR EACH ROW
    EXECUTE FUNCTION public.cleanup_event_invite_notifications();
