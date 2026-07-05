-- Redress: block sending outfit suggestions when recipient already owns the same item combination.
-- Requires SUPABASE_OUTFIT_SUGGESTIONS.sql helpers (redress_item_ids_are_valid, outfit_suggestion_matches_wardrobe).
-- Run in Supabase SQL Editor.

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

DROP FUNCTION IF EXISTS public.find_recipient_duplicate_outfit(uuid, text);

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

-- Enforce on send (replaces create_outfit_suggestion body — same signature as SUPABASE_OUTFIT_SUGGESTIONS.sql).
DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, text, text);

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
