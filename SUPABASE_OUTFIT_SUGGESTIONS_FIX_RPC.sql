-- Fix: create_outfit_suggestion rejected items when mobile client sent JSON as text.
-- Re-run this in Supabase SQL Editor if Send shows "At least one item is required".

DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.create_outfit_suggestion(uuid, uuid, text, text, text, jsonb, jsonb);

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
