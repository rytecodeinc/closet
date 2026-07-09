-- Submitter withdraw pending Redress outfit suggestions.
-- Run in Supabase SQL Editor after SUPABASE_OUTFIT_SUGGESTIONS.sql.

DROP FUNCTION IF EXISTS public.withdraw_redress(uuid);

CREATE OR REPLACE FUNCTION public.withdraw_redress(p_suggestion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  UPDATE public.outfit_suggestions
  SET
    status = 'withdrawn',
    updated_at = now()
  WHERE id = p_suggestion_id
    AND suggester_user_id = auth.uid()
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Suggestion not found or not withdrawable';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_redress(uuid) TO authenticated;
