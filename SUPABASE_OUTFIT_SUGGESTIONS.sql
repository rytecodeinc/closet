-- Outfit suggestions (Redress): pending outfit proposals from one user to another.
-- Requires SUPABASE_REDRESS_WARDROBES_RPC.sql (allow_outfit_suggestions) applied.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.outfit_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  suggester_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'withdrawn')),
  proposed_name text,
  proposed_notes text,
  image_url text,
  transformation_json jsonb,
  item_ids uuid[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outfit_suggestions_not_self CHECK (recipient_user_id <> suggester_user_id)
);

CREATE INDEX IF NOT EXISTS outfit_suggestions_recipient_status_idx
  ON public.outfit_suggestions (recipient_user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS outfit_suggestions_suggester_status_idx
  ON public.outfit_suggestions (suggester_user_id, status, created_at DESC);

COMMENT ON TABLE public.outfit_suggestions IS
  'Redress outfit proposals. Pending until recipient accepts/rejects.';

ALTER TABLE public.outfit_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Suggester can read own outfit suggestions" ON public.outfit_suggestions;
CREATE POLICY "Suggester can read own outfit suggestions"
ON public.outfit_suggestions FOR SELECT
USING (suggester_user_id = auth.uid());

DROP POLICY IF EXISTS "Recipient can read outfit suggestions for them" ON public.outfit_suggestions;
CREATE POLICY "Recipient can read outfit suggestions for them"
ON public.outfit_suggestions FOR SELECT
USING (recipient_user_id = auth.uid());

-- Inserts/updates go through SECURITY DEFINER RPCs only.

DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, jsonb, uuid[]);
DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, text, text, text, jsonb, uuid[]);
DROP FUNCTION IF EXISTS public.get_viewer_outfit_suggestions_for_wardrobe(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_recipient_outfit_suggestions_for_wardrobe(uuid);

-- Returns true when every item in p_item_ids belongs to p_recipient and is redress-accessible to auth.uid().
CREATE OR REPLACE FUNCTION public.redress_item_ids_are_valid(
  p_recipient_id uuid,
  p_item_ids uuid[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public AS
$$
  WITH viewer AS (
    SELECT auth.uid() AS uid
  ),
  recipient_allowed AS (
    SELECT up.user_id
    FROM public.user_profiles up
    WHERE up.user_id = p_recipient_id
      AND COALESCE(up.allow_outfit_suggestions, true) = true
  ),
  viewer_blocked AS (
    SELECT 1
    FROM public.friendships f
    CROSS JOIN viewer v
    WHERE v.uid IS NOT NULL
      AND f.status = 'blocked'
      AND (
        (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
        OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
      )
  ),
  viewer_is_friend AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.friendships f
      CROSS JOIN viewer v
      WHERE v.uid IS NOT NULL
        AND f.status = 'accepted'
        AND (
          (f.user_id = v.uid AND f.friend_user_id = p_recipient_id)
          OR (f.friend_user_id = v.uid AND f.user_id = p_recipient_id)
        )
    ) AS value
  ),
  allowed_wardrobe_ids AS (
    SELECT w.id
    FROM public.wardrobes w
    CROSS JOIN viewer v
    CROSS JOIN recipient_allowed r
    CROSS JOIN viewer_is_friend f
    WHERE v.uid IS NOT NULL
      AND v.uid <> p_recipient_id
      AND NOT EXISTS (SELECT 1 FROM viewer_blocked)
      AND w.user_id = p_recipient_id
      AND COALESCE(w.is_soft_deleted, false) = false
      AND (
        w.visibility = 'public'
        OR (f.value AND w.visibility = 'friends')
      )
  ),
  requested_items AS (
    SELECT unnest(p_item_ids) AS item_id
  )
  SELECT
    COALESCE(array_length(p_item_ids, 1), 0) > 0
    AND NOT EXISTS (
      SELECT 1
      FROM requested_items ri
      LEFT JOIN public.items i ON i.id = ri.item_id
      WHERE i.id IS NULL
        OR i.user_id <> p_recipient_id
        OR COALESCE(i.is_soft_deleted, false) = true
        OR COALESCE(i.is_draft, false) = true
        OR NOT EXISTS (
          SELECT 1
          FROM public.item_wardrobes iw
          INNER JOIN allowed_wardrobe_ids aw ON aw.id = iw.wardrobe_id
          WHERE iw.item_id = i.id
        )
    );
$$;

GRANT EXECUTE ON FUNCTION public.redress_item_ids_are_valid(uuid, uuid[]) TO authenticated;

-- Sorted active item ids for a recipient outfit (non-draft, non-deleted items only).
CREATE OR REPLACE FUNCTION public.outfit_active_item_ids(p_outfit_id uuid, p_user_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT coalesce(
    array_agg(oi.item_id ORDER BY oi.item_id),
    '{}'::uuid[]
  )
  FROM public.outfit_items oi
  INNER JOIN public.items i ON i.id = oi.item_id
  WHERE oi.outfit_id = p_outfit_id
    AND i.user_id = p_user_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false;
$$;

GRANT EXECUTE ON FUNCTION public.outfit_active_item_ids(uuid, uuid) TO authenticated;

-- True when recipient already owns a non-draft outfit with the exact same item set (order ignored).
CREATE OR REPLACE FUNCTION public.recipient_has_duplicate_outfit(
  p_recipient_id uuid,
  p_item_ids uuid[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public AS
$$
  WITH requested AS (
    SELECT coalesce(array_agg(x ORDER BY x), '{}'::uuid[]) AS ids
    FROM unnest(p_item_ids) AS x
  )
  SELECT EXISTS (
    SELECT 1
    FROM public.outfits o
    CROSS JOIN requested r
    WHERE o.user_id = p_recipient_id
      AND COALESCE(o.is_soft_deleted, false) = false
      AND COALESCE(o.is_draft, false) = false
      AND COALESCE(array_length(r.ids, 1), 0) > 0
      AND public.outfit_active_item_ids(o.id, p_recipient_id) = r.ids
  );
$$;

GRANT EXECUTE ON FUNCTION public.recipient_has_duplicate_outfit(uuid, uuid[]) TO authenticated;

-- Suggestion appears on a wardrobe when at least one item belongs to that wardrobe
-- (allows mixed Closet/Wishlist Redress; owner can see private wardrobes).
CREATE OR REPLACE FUNCTION public.outfit_suggestion_matches_wardrobe(
  p_recipient_id uuid,
  p_wardrobe_id uuid,
  p_item_ids uuid[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public AS
$$
  WITH target_wardrobe AS (
    SELECT w.id
    FROM public.wardrobes w
    WHERE w.id = p_wardrobe_id
      AND w.user_id = p_recipient_id
      AND COALESCE(w.is_soft_deleted, false) = false
      AND (
        auth.uid() = p_recipient_id
        OR w.visibility = 'public'
        OR (
          w.visibility = 'friends'
          AND EXISTS (
            SELECT 1
            FROM public.friendships f
            WHERE f.status = 'accepted'
              AND (
                (f.user_id = auth.uid() AND f.friend_user_id = p_recipient_id)
                OR (f.friend_user_id = auth.uid() AND f.user_id = p_recipient_id)
              )
          )
        )
      )
  ),
  suggestion_items AS (
    SELECT i.id AS item_id
    FROM unnest(p_item_ids) AS req(item_id)
    INNER JOIN public.items i ON i.id = req.item_id
    WHERE i.user_id = p_recipient_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false
  )
  SELECT EXISTS (SELECT 1 FROM target_wardrobe)
    AND EXISTS (
      SELECT 1
      FROM suggestion_items si
      INNER JOIN public.item_wardrobes iw
        ON iw.item_id = si.item_id
       AND iw.wardrobe_id = p_wardrobe_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.outfit_suggestion_matches_wardrobe(uuid, uuid, uuid[]) TO authenticated;

DROP FUNCTION IF EXISTS public.find_recipient_duplicate_outfit(uuid, text);

-- Pre-send duplicate check for Redress: returns one matching recipient outfit + a redress-accessible wardrobe id.
CREATE OR REPLACE FUNCTION public.find_recipient_duplicate_outfit(
  p_recipient_id uuid,
  p_item_ids text
)
RETURNS TABLE (
  outfit_id uuid,
  name text,
  image_url text,
  wardrobe_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_sorted_ids uuid[];
  v_item_ids_json jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  v_item_ids_json := coalesce(nullif(trim(p_item_ids), ''), '[]')::jsonb;
  IF jsonb_typeof(v_item_ids_json) = 'string' THEN
    v_item_ids_json := (v_item_ids_json #>> '{}')::jsonb;
  END IF;

  SELECT coalesce(array_agg(value::uuid ORDER BY value::uuid), '{}'::uuid[])
  INTO v_sorted_ids
  FROM jsonb_array_elements_text(v_item_ids_json) AS t(value);

  IF COALESCE(array_length(v_sorted_ids, 1), 0) = 0 THEN
    RETURN;
  END IF;

  IF NOT public.redress_item_ids_are_valid(p_recipient_id, v_sorted_ids) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH match AS (
    SELECT o.id, o.name, o.image_url
    FROM public.outfits o
    WHERE o.user_id = p_recipient_id
      AND COALESCE(o.is_soft_deleted, false) = false
      AND COALESCE(o.is_draft, false) = false
      AND public.outfit_active_item_ids(o.id, p_recipient_id) = v_sorted_ids
    ORDER BY o.created_at DESC NULLS LAST, o.name
    LIMIT 1
  )
  SELECT
    m.id,
    m.name,
    m.image_url,
    (
      SELECT rw.id
      FROM public.get_redress_wardrobes(p_recipient_id) rw
      WHERE public.outfit_suggestion_matches_wardrobe(p_recipient_id, rw.id, v_sorted_ids)
      ORDER BY rw.is_default DESC, lower(coalesce(rw.type, ''))
      LIMIT 1
    )
  FROM match m;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_recipient_duplicate_outfit(uuid, text) TO authenticated;

DROP FUNCTION IF EXISTS public.get_redress_outfit_detail(uuid, uuid, uuid);

-- Read-only outfit detail when viewer is composing Redress for p_recipient_id (public or friends wardrobes).
CREATE OR REPLACE FUNCTION public.get_redress_outfit_detail(
  p_recipient_id uuid,
  p_outfit_id uuid,
  p_wardrobe_id uuid
)
RETURNS TABLE (
  outfit_id uuid,
  name text,
  notes text,
  image_url text,
  worn_image_url text,
  created_at timestamptz,
  item_thumbnails jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    o.id AS outfit_id,
    o.name,
    o.notes,
    o.image_url,
    o.worn_image_url,
    o.created_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_id', i.id,
            'name', i.name,
            'thumbnail_url', COALESCE(
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM public.item_photos p
                WHERE p.item_id = i.id
                  AND COALESCE(p.is_primary, false) = true
                LIMIT 1
              ),
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM public.item_photos p
                WHERE p.item_id = i.id
                ORDER BY p.created_at NULLS LAST
                LIMIT 1
              )
            )
          )
          ORDER BY oi.item_id
        )
        FROM public.outfit_items oi
        INNER JOIN public.items i ON i.id = oi.item_id
        WHERE oi.outfit_id = o.id
          AND COALESCE(i.is_soft_deleted, false) = false
          AND COALESCE(i.is_draft, false) = false
      ),
      '[]'::jsonb
    ) AS item_thumbnails
  FROM public.outfits o
  WHERE o.id = p_outfit_id
    AND o.user_id = p_recipient_id
    AND COALESCE(o.is_soft_deleted, false) = false
    AND COALESCE(o.is_draft, false) = false
    AND EXISTS (
      SELECT 1
      FROM public.get_redress_wardrobes(p_recipient_id) rw
      WHERE rw.id = p_wardrobe_id
    )
    AND public.outfit_suggestion_matches_wardrobe(
      p_recipient_id,
      p_wardrobe_id,
      public.outfit_active_item_ids(o.id, p_recipient_id)
    )
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_redress_outfit_detail(uuid, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_outfit_suggestion(
  p_suggestion_id uuid,
  p_recipient_id uuid,
  p_proposed_name text,
  p_proposed_notes text,
  p_image_url text,
  p_transformation_json text,
  p_item_ids text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_suggester uuid := auth.uid();
  v_id uuid := COALESCE(p_suggestion_id, gen_random_uuid());
  v_item_ids uuid[];
  v_item_ids_json jsonb;
  v_transformation_json jsonb;
BEGIN
  -- PostgREST / mobile clients often send JSON arrays as text; normalize to jsonb.
  v_item_ids_json := coalesce(nullif(trim(p_item_ids), ''), '[]')::jsonb;
  IF jsonb_typeof(v_item_ids_json) = 'string' THEN
    v_item_ids_json := (v_item_ids_json #>> '{}')::jsonb;
  END IF;

  v_transformation_json := coalesce(nullif(trim(p_transformation_json), ''), '[]')::jsonb;
  IF jsonb_typeof(v_transformation_json) = 'string' THEN
    v_transformation_json := (v_transformation_json #>> '{}')::jsonb;
  END IF;

  IF v_item_ids_json IS NULL
    OR jsonb_typeof(v_item_ids_json) <> 'array'
    OR jsonb_array_length(v_item_ids_json) = 0 THEN
    RAISE EXCEPTION 'At least one item is required';
  END IF;

  SELECT coalesce(array_agg(value::uuid), '{}')
  INTO v_item_ids
  FROM jsonb_array_elements_text(v_item_ids_json);

  IF COALESCE(array_length(v_item_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'At least one item is required';
  END IF;
  IF v_suggester IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF v_suggester = p_recipient_id THEN
    RAISE EXCEPTION 'Cannot suggest an outfit to yourself';
  END IF;

  IF NOT public.redress_item_ids_are_valid(p_recipient_id, v_item_ids) THEN
    RAISE EXCEPTION 'One or more items are not available for Redress';
  END IF;

  IF public.recipient_has_duplicate_outfit(p_recipient_id, v_item_ids) THEN
    RAISE EXCEPTION 'Recipient already has an outfit with these items';
  END IF;

  INSERT INTO public.outfit_suggestions (
    id,
    recipient_user_id,
    suggester_user_id,
    status,
    proposed_name,
    proposed_notes,
    image_url,
    transformation_json,
    item_ids
  ) VALUES (
    v_id,
    p_recipient_id,
    v_suggester,
    'pending',
    NULLIF(trim(p_proposed_name), ''),
    NULLIF(trim(p_proposed_notes), ''),
    NULLIF(trim(p_image_url), ''),
    v_transformation_json,
    v_item_ids
  );

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_outfit_suggestion(uuid, uuid, text, text, text, text, text) TO authenticated;

-- Pending suggestions sent by the current viewer to p_recipient_id, visible on p_wardrobe_id outfits tab.
CREATE OR REPLACE FUNCTION public.get_viewer_outfit_suggestions_for_wardrobe(
  p_recipient_id uuid,
  p_wardrobe_id uuid
)
RETURNS TABLE (
  suggestion_id uuid,
  name text,
  image_url text,
  suggester_user_id uuid,
  suggester_username text,
  suggester_display_name text,
  suggester_avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    s.id AS suggestion_id,
    s.proposed_name AS name,
    s.image_url,
    s.suggester_user_id,
    up.username AS suggester_username,
    up.display_name AS suggester_display_name,
    up.avatar_url AS suggester_avatar_url
  FROM public.outfit_suggestions s
  LEFT JOIN public.user_profiles up ON up.user_id = s.suggester_user_id
  WHERE s.suggester_user_id = auth.uid()
    AND s.recipient_user_id = p_recipient_id
    AND s.status = 'pending'
    AND public.outfit_suggestion_matches_wardrobe(p_recipient_id, p_wardrobe_id, s.item_ids)
  ORDER BY s.created_at DESC NULLS LAST, s.proposed_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_viewer_outfit_suggestions_for_wardrobe(uuid, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.get_recipient_outfit_suggestions_for_wardrobe(uuid);

-- Pending Redress suggestions received by auth.uid(), scoped to a wardrobe (profile / outfits tab).
CREATE OR REPLACE FUNCTION public.get_recipient_outfit_suggestions_for_wardrobe(
  p_wardrobe_id uuid
)
RETURNS TABLE (
  suggestion_id uuid,
  name text,
  image_url text,
  suggester_user_id uuid,
  suggester_username text,
  suggester_display_name text,
  suggester_avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    s.id AS suggestion_id,
    s.proposed_name AS name,
    s.image_url,
    s.suggester_user_id,
    up.username AS suggester_username,
    up.display_name AS suggester_display_name,
    up.avatar_url AS suggester_avatar_url
  FROM public.outfit_suggestions s
  LEFT JOIN public.user_profiles up ON up.user_id = s.suggester_user_id
  WHERE s.recipient_user_id = auth.uid()
    AND s.status = 'pending'
    AND public.outfit_suggestion_matches_wardrobe(s.recipient_user_id, p_wardrobe_id, s.item_ids)
  ORDER BY s.created_at DESC NULLS LAST, s.proposed_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_recipient_outfit_suggestions_for_wardrobe(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.get_outfit_redress_suggestion_context(uuid);

-- Redress metadata for a received suggestion (recipient only) — includes suggester profile fields via SECURITY DEFINER join.
CREATE OR REPLACE FUNCTION public.get_outfit_redress_suggestion_context(p_suggestion_id uuid)
RETURNS TABLE (
  suggestion_id uuid,
  status text,
  suggester_user_id uuid,
  suggester_username text,
  suggester_display_name text,
  suggester_avatar_url text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    s.id AS suggestion_id,
    s.status,
    s.suggester_user_id,
    up.username AS suggester_username,
    up.display_name AS suggester_display_name,
    up.avatar_url AS suggester_avatar_url,
    s.created_at
  FROM public.outfit_suggestions s
  LEFT JOIN public.user_profiles up ON up.user_id = s.suggester_user_id
  WHERE s.id = p_suggestion_id
    AND s.recipient_user_id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_outfit_redress_suggestion_context(uuid) TO authenticated;

-- Read-only detail for a pending Redress outfit suggestion (suggester or recipient).
DROP FUNCTION IF EXISTS public.get_outfit_suggestion_detail(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_outfit_suggestion_detail(
  p_suggestion_id uuid,
  p_recipient_id uuid,
  p_wardrobe_id uuid
)
RETURNS TABLE (
  suggestion_id uuid,
  proposed_name text,
  proposed_notes text,
  image_url text,
  created_at timestamptz,
  item_thumbnails jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH suggestion AS (
    SELECT s.*
    FROM public.outfit_suggestions s
    WHERE s.id = p_suggestion_id
      AND s.recipient_user_id = p_recipient_id
      AND s.status = 'pending'
      AND (s.suggester_user_id = auth.uid() OR s.recipient_user_id = auth.uid())
      AND (
        (
          s.suggester_user_id = auth.uid()
          AND public.outfit_suggestion_matches_wardrobe(p_recipient_id, p_wardrobe_id, s.item_ids)
        )
        OR s.recipient_user_id = auth.uid()
      )
  ),
  ordered_item_ids AS (
    SELECT u.item_id, u.sort_order
    FROM suggestion s
    CROSS JOIN LATERAL (
      SELECT ARRAY(
        SELECT NULLIF(trim(elem->>'itemID'), '')::uuid
        FROM jsonb_array_elements(
          CASE
            WHEN jsonb_typeof(s.transformation_json) = 'array'
              AND jsonb_array_length(s.transformation_json) > 0
            THEN s.transformation_json
            ELSE '[]'::jsonb
          END
        ) AS elem
        WHERE NULLIF(trim(elem->>'itemID'), '') IS NOT NULL
      ) AS transformation_ids
    ) ti
    CROSS JOIN LATERAL unnest(
      CASE
        WHEN COALESCE(array_length(ti.transformation_ids, 1), 0) > 0 THEN ti.transformation_ids
        ELSE s.item_ids
      END
    ) WITH ORDINALITY AS u(item_id, sort_order)
  )
  SELECT
    s.id AS suggestion_id,
    s.proposed_name,
    s.proposed_notes,
    s.image_url,
    s.created_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'item_id', i.id,
            'name', i.name,
            'thumbnail_url', COALESCE(
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM item_photos p
                WHERE p.item_id = i.id
                  AND COALESCE(p.is_primary, false) = true
                LIMIT 1
              ),
              (
                SELECT COALESCE(p.thumbnail_url, p.image_url)
                FROM item_photos p
                WHERE p.item_id = i.id
                ORDER BY p.created_at NULLS LAST
                LIMIT 1
              )
            )
          )
          ORDER BY oi.sort_order
        )
        FROM ordered_item_ids oi
        INNER JOIN public.items i ON i.id = oi.item_id
        WHERE COALESCE(i.is_soft_deleted, false) = false
          AND COALESCE(i.is_draft, false) = false
      ),
      '[]'::jsonb
    ) AS item_thumbnails
  FROM suggestion s
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_outfit_suggestion_detail(uuid, uuid, uuid) TO authenticated;

-- Notify recipient when a Redress outfit suggestion is created.
CREATE OR REPLACE FUNCTION public.notify_outfit_suggestion_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_suggester_username text;
  v_suggester_display text;
  v_label text;
BEGIN
  SELECT up.username, up.display_name
  INTO v_suggester_username, v_suggester_display
  FROM public.user_profiles up
  WHERE up.user_id = NEW.suggester_user_id;

  v_label := coalesce(
    nullif(trim(v_suggester_display), ''),
    nullif(trim(v_suggester_username), ''),
    'Someone'
  );

  INSERT INTO public.notifications (user_id, type, title, body, payload)
  VALUES (
    NEW.recipient_user_id,
    'outfit_suggestion',
    v_label || ' redressed you',
    NULL,
    jsonb_build_object(
      'suggestion_id', NEW.id::text,
      'suggester_user_id', NEW.suggester_user_id::text,
      'image_url', NEW.image_url
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS outfit_suggestion_notify_recipient ON public.outfit_suggestions;
CREATE TRIGGER outfit_suggestion_notify_recipient
  AFTER INSERT ON public.outfit_suggestions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_outfit_suggestion_created();

-- Recipient accepts or declines a pending Redress outfit suggestion.
DROP FUNCTION IF EXISTS public.respond_to_outfit_suggestion(uuid, boolean);
DROP FUNCTION IF EXISTS public.respond_to_outfit_suggestion(uuid, text);

CREATE OR REPLACE FUNCTION public.respond_to_outfit_suggestion(
  p_suggestion_id uuid,
  p_accept text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_accept boolean := coalesce(nullif(trim(p_accept), ''), 'false')::boolean;
BEGIN
  UPDATE public.outfit_suggestions
  SET
    status = CASE WHEN v_accept THEN 'accepted' ELSE 'declined' END,
    updated_at = now()
  WHERE id = p_suggestion_id
    AND recipient_user_id = auth.uid()
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Suggestion not found or not actionable';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_to_outfit_suggestion(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Migrate existing `outfit_suggestions` status: rejected → declined (friends parity)
-- Safe to re-run after CREATE TABLE IF NOT EXISTS (does not alter CHECK on existing tables).
-- ---------------------------------------------------------------------------
UPDATE public.outfit_suggestions
SET status = 'declined'
WHERE status = 'rejected';

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid = 'public.outfit_suggestions'::regclass
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.outfit_suggestions DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.outfit_suggestions
  ADD CONSTRAINT outfit_suggestions_status_check
  CHECK (status IN ('pending', 'accepted', 'declined', 'withdrawn'));
