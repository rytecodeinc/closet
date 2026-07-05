-- Suggester profile fields on pending Redress RPCs + outfit detail context (SECURITY DEFINER joins).
-- Run in Supabase SQL Editor after SUPABASE_OUTFIT_SUGGESTIONS.sql.

DROP FUNCTION IF EXISTS public.get_viewer_outfit_suggestions_for_wardrobe(uuid, uuid);

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
