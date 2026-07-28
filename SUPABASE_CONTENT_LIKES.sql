-- Social likes on items and outfits (other users tapping heart on read-only detail).
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.content_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  target_type text NOT NULL CHECK (target_type IN ('item', 'outfit')),
  target_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT content_likes_user_target_unique UNIQUE (user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_content_likes_target
  ON public.content_likes (target_type, target_id);

ALTER TABLE public.content_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can select content likes" ON public.content_likes;
CREATE POLICY "Users can select content likes"
ON public.content_likes FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Users can insert own content likes" ON public.content_likes;
CREATE POLICY "Users can insert own content likes"
ON public.content_likes FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own content likes" ON public.content_likes;
CREATE POLICY "Users can delete own content likes"
ON public.content_likes FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- Returns like_count + whether the caller has liked this target.
CREATE OR REPLACE FUNCTION public.get_content_like_state(
  p_target_type text,
  p_target_id uuid
)
RETURNS TABLE (
  like_count integer,
  liked_by_me boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    (
      SELECT COUNT(*)::integer
      FROM public.content_likes cl
      WHERE cl.target_type = p_target_type
        AND cl.target_id = p_target_id
    ) AS like_count,
    EXISTS (
      SELECT 1
      FROM public.content_likes cl
      WHERE cl.target_type = p_target_type
        AND cl.target_id = p_target_id
        AND cl.user_id = auth.uid()
    ) AS liked_by_me;
$$;

GRANT EXECUTE ON FUNCTION public.get_content_like_state(text, uuid) TO authenticated;

-- Toggle like for the caller. Cannot like own items/outfits.
CREATE OR REPLACE FUNCTION public.toggle_content_like(
  p_target_type text,
  p_target_id uuid
)
RETURNS TABLE (
  like_count integer,
  liked_by_me boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_owner uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_target_type IS DISTINCT FROM 'item' AND p_target_type IS DISTINCT FROM 'outfit' THEN
    RAISE EXCEPTION 'Invalid target_type';
  END IF;

  IF p_target_type = 'item' THEN
    SELECT i.user_id INTO v_owner
    FROM public.items i
    WHERE i.id = p_target_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false;
  ELSE
    SELECT o.user_id INTO v_owner
    FROM public.outfits o
    WHERE o.id = p_target_id
      AND COALESCE(o.is_soft_deleted, false) = false
      AND COALESCE(o.is_draft, false) = false;
  END IF;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Content not found';
  END IF;

  IF v_owner = auth.uid() THEN
    RAISE EXCEPTION 'Cannot like your own content';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.content_likes cl
    WHERE cl.user_id = auth.uid()
      AND cl.target_type = p_target_type
      AND cl.target_id = p_target_id
  ) THEN
    DELETE FROM public.content_likes cl
    WHERE cl.user_id = auth.uid()
      AND cl.target_type = p_target_type
      AND cl.target_id = p_target_id;
  ELSE
    INSERT INTO public.content_likes (user_id, target_type, target_id)
    VALUES (auth.uid(), p_target_type, p_target_id);
  END IF;

  RETURN QUERY
  SELECT * FROM public.get_content_like_state(p_target_type, p_target_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.toggle_content_like(text, uuid) TO authenticated;

-- Owner notifications when liked: see SUPABASE_CONTENT_LIKE_NOTIFICATIONS.sql
