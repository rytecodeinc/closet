-- Cap in-app notifications: newest 30 per (user_id, type).
-- No time-based TTL. Fewer than 30 of a type are all kept.
-- Exempt until resolved (never deleted by this cap):
--   unread friend_request
--   unread outfit_suggestion (pending Redress)
-- Likes, shares, friend_accepted, and read/responded Redress are eligible.
-- Requires: notifications table.
-- Run in the Supabase SQL editor.

CREATE INDEX IF NOT EXISTS idx_notifications_user_type_created
  ON public.notifications (user_id, type, created_at DESC, id DESC);

CREATE OR REPLACE FUNCTION public.notification_is_retention_exempt(
  p_type text,
  p_is_read boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    (p_type = 'friend_request' AND p_is_read = false)
    OR (p_type = 'outfit_suggestion' AND p_is_read = false);
$$;

CREATE OR REPLACE FUNCTION public.prune_notifications_for_user_type(
  p_user_id uuid,
  p_type text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  WITH keep AS (
    SELECT n.id
    FROM public.notifications n
    WHERE n.user_id = p_user_id
      AND n.type = p_type
      AND NOT public.notification_is_retention_exempt(n.type, n.is_read)
    ORDER BY n.created_at DESC, n.id DESC
    LIMIT 30
  )
  DELETE FROM public.notifications n
  WHERE n.user_id = p_user_id
    AND n.type = p_type
    AND NOT public.notification_is_retention_exempt(n.type, n.is_read)
    AND NOT EXISTS (
      SELECT 1 FROM keep k WHERE k.id = n.id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.prune_notifications_for_user_type(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_notifications_for_user_type(uuid, text) FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.prune_notifications_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_user_id uuid;
  v_type text;
BEGIN
  -- Nested DELETE from prune must not re-enter (same-table trigger recursion / lock wait).
  IF pg_trigger_depth() > 1 THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  v_user_id := NEW.user_id;
  v_type := NEW.type;
  PERFORM public.prune_notifications_for_user_type(v_user_id, v_type);
  RETURN NEW;
END;
$$;

-- Statement-level prune after mark-as-read (one pass per type, not per row).
CREATE OR REPLACE FUNCTION public.prune_notifications_after_read_statement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  r record;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;

  -- Postgres forbids transition tables on "UPDATE OF column" triggers.
  FOR r IN
    SELECT DISTINCT n.user_id, n.type
    FROM new_rows n
    JOIN old_rows o ON o.id = n.id
    WHERE o.is_read IS DISTINCT FROM n.is_read
  LOOP
    PERFORM public.prune_notifications_for_user_type(r.user_id, r.type);
  END LOOP;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS notifications_prune_after_insert ON public.notifications;
CREATE TRIGGER notifications_prune_after_insert
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.prune_notifications_after_change();

DROP TRIGGER IF EXISTS notifications_prune_after_read ON public.notifications;
CREATE TRIGGER notifications_prune_after_read
  AFTER UPDATE ON public.notifications
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.prune_notifications_after_read_statement();

-- One-time cleanup of existing rows over the cap.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT user_id, type
    FROM public.notifications
  LOOP
    PERFORM public.prune_notifications_for_user_type(r.user_id, r.type);
  END LOOP;
END
$$;
