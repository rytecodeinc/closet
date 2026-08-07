-- Submitter revises a pending Redress outfit suggestion in place.
-- Run in Supabase SQL Editor after SUPABASE_OUTFIT_SUGGESTIONS.sql.

DROP FUNCTION IF EXISTS public.update_pending_outfit_suggestion(uuid, uuid, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.update_pending_outfit_suggestion(
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
  v_item_ids uuid[];
  v_item_ids_json jsonb;
  v_transformation_json jsonb;
  v_updated_id uuid;
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

  UPDATE public.outfit_suggestions
  SET
    proposed_name = NULLIF(trim(p_proposed_name), ''),
    proposed_notes = NULLIF(trim(p_proposed_notes), ''),
    image_url = NULLIF(trim(p_image_url), ''),
    transformation_json = v_transformation_json,
    item_ids = v_item_ids,
    updated_at = now()
  WHERE id = p_suggestion_id
    AND suggester_user_id = v_suggester
    AND recipient_user_id = p_recipient_id
    AND status = 'pending'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'Suggestion not found or not editable';
  END IF;

  RETURN v_updated_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_pending_outfit_suggestion(uuid, uuid, text, text, text, text, text) TO authenticated;
