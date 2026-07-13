-- Device tokens for native APNs push (iOS).
-- Run in Supabase SQL Editor before deploying the send-push Edge Function.
-- Requires: auth.users / authenticated role.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'ios',
  environment text NOT NULL DEFAULT 'sandbox', -- 'sandbox' | 'production'
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_platform_check CHECK (platform IN ('ios')),
  CONSTRAINT device_tokens_environment_check CHECK (environment IN ('sandbox', 'production'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_token
  ON public.device_tokens (token);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
  ON public.device_tokens (user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can select own device tokens" ON public.device_tokens;
CREATE POLICY "Users can select own device tokens"
ON public.device_tokens FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own device tokens" ON public.device_tokens;
CREATE POLICY "Users can insert own device tokens"
ON public.device_tokens FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own device tokens" ON public.device_tokens;
CREATE POLICY "Users can update own device tokens"
ON public.device_tokens FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own device tokens" ON public.device_tokens;
CREATE POLICY "Users can delete own device tokens"
ON public.device_tokens FOR DELETE
USING (user_id = auth.uid());

-- Upsert helper for clients (optional; clients may upsert via PostgREST).
CREATE OR REPLACE FUNCTION public.upsert_device_token(
  p_token text,
  p_platform text DEFAULT 'ios',
  p_environment text DEFAULT 'sandbox'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.device_tokens (user_id, token, platform, environment, updated_at)
  VALUES (auth.uid(), p_token, p_platform, p_environment, now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = excluded.user_id,
        platform = excluded.platform,
        environment = excluded.environment,
        updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_device_token(text, text, text) TO authenticated;
