-- Optional: invoke send-push Edge Function after each notifications INSERT.
-- Prefer configuring a Database Webhook in the Supabase Dashboard (Database → Webhooks)
-- pointing at: https://<PROJECT_REF>.supabase.co/functions/v1/send-push
--
-- If you use pg_net instead, enable the extension and set the URL/service role below,
-- then run this file. Replace PROJECT_REF and YOUR_SERVICE_ROLE_KEY.

-- CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.notify_send_push_on_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  -- Set these after deploy (or use Dashboard webhook and skip this trigger).
  edge_url text := current_setting('app.settings.send_push_url', true);
  service_key text := current_setting('app.settings.service_role_key', true);
BEGIN
  IF edge_url IS NULL OR edge_url = '' OR service_key IS NULL OR service_key = '' THEN
    -- Not configured; Database Webhook path should be used instead.
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'notifications',
      'schema', 'public',
      'record', to_jsonb(NEW)
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notifications_send_push ON public.notifications;
-- Uncomment after setting app.settings.send_push_url and app.settings.service_role_key
-- and enabling extensions.pg_net:
-- CREATE TRIGGER notifications_send_push
--   AFTER INSERT ON public.notifications
--   FOR EACH ROW
--   EXECUTE FUNCTION public.notify_send_push_on_notification();
