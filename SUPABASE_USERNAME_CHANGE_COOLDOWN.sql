-- Username change cooldown: once every 30 days.
-- Safe to re-run.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS username_changed_at timestamptz;

COMMENT ON COLUMN public.user_profiles.username_changed_at IS
  'When username was last changed; next change allowed after 30 days. NULL = never changed (or pre-migration).';

CREATE OR REPLACE FUNCTION public.enforce_username_change_cooldown()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.username IS DISTINCT FROM OLD.username THEN
    IF OLD.username_changed_at IS NOT NULL
       AND OLD.username_changed_at > (now() - interval '30 days') THEN
      RAISE EXCEPTION 'Username can only be changed once every 30 days'
        USING ERRCODE = 'P0001';
    END IF;
    NEW.username_changed_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_profiles_username_change_cooldown ON public.user_profiles;

CREATE TRIGGER trg_user_profiles_username_change_cooldown
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_username_change_cooldown();
