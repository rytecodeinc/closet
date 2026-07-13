-- Fix duplicate friend_request notifications.
-- Cause: an older friendships trigger still inserts title 'New friend request'
-- alongside friendship_notify_request → '{name} sent you a friend request'.
--
-- Run in Supabase SQL Editor (once). Safe to re-run.

-- 1) Drop non-canonical friendships triggers that write notifications
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname, p.prosrc
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.friendships'::regclass
      AND NOT t.tgisinternal
      AND t.tgname NOT IN (
        'friendship_notify_request',
        'friendship_notify_accepted',
        'friendship_cleanup_request_notifications'
      )
  LOOP
    IF r.prosrc ILIKE '%notifications%'
       OR r.prosrc ILIKE '%friend_request%'
       OR r.prosrc ILIKE '%New friend%' THEN
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.friendships', r.tgname);
      RAISE NOTICE 'Dropped duplicate trigger: %', r.tgname;
    END IF;
  END LOOP;
END $$;

-- 2) Drop known legacy function names (no-op if missing)
DROP FUNCTION IF EXISTS public.notify_on_friendship_insert() CASCADE;
DROP FUNCTION IF EXISTS public.handle_friendship_notification() CASCADE;
DROP FUNCTION IF EXISTS public.create_friend_request_notification() CASCADE;
DROP FUNCTION IF EXISTS public.on_friendship_created() CASCADE;
DROP FUNCTION IF EXISTS public.friendships_create_notification() CASCADE;

-- 3) Remove existing generic duplicates (keep the named title)
DELETE FROM public.notifications
WHERE type = 'friend_request'
  AND title = 'New friend request';

-- 4) Re-apply canonical trigger (idempotent insert + named title)
CREATE OR REPLACE FUNCTION public.notify_friend_request_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_requester_username text;
  v_requester_display text;
  v_label text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id = NEW.friend_user_id THEN
    RETURN NEW;
  END IF;

  -- Avoid duplicates if another path already wrote this friendship.
  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.type = 'friend_request'
      AND (n.payload->>'friendship_id') = NEW.id::text
  ) THEN
    RETURN NEW;
  END IF;

  SELECT up.username, up.display_name
  INTO v_requester_username, v_requester_display
  FROM public.user_profiles up
  WHERE up.user_id = NEW.user_id;

  v_label := coalesce(
    nullif(trim(v_requester_display), ''),
    nullif(trim(v_requester_username), ''),
    'Someone'
  );

  INSERT INTO public.notifications (user_id, type, title, body, payload)
  VALUES (
    NEW.friend_user_id,
    'friend_request',
    v_label || ' sent you a friend request',
    NULL,
    jsonb_build_object(
      'friendship_id', NEW.id::text,
      'from_user_id', NEW.user_id::text,
      'from_username', v_requester_username
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS friendship_notify_request ON public.friendships;
CREATE TRIGGER friendship_notify_request
  AFTER INSERT ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_friend_request_created();
