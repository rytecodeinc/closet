-- Friendship → in-app notifications
-- Requires: friendships table, notifications table, user_profiles.
-- Run in Supabase SQL Editor after SUPABASE_FRIENDSHIPS_TABLE.sql and SUPABASE_NOTIFICATIONS_TABLE.sql.

-- 1) Pending friend request → notify recipient
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

  -- Idempotent: one notification per friendship_id
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

-- 2) Accept → notify original requester
CREATE OR REPLACE FUNCTION public.notify_friend_request_accepted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_accepter_username text;
  v_accepter_display text;
  v_label text;
BEGIN
  IF NOT (
    OLD.status = 'pending'
    AND NEW.status = 'accepted'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT up.username, up.display_name
  INTO v_accepter_username, v_accepter_display
  FROM public.user_profiles up
  WHERE up.user_id = NEW.friend_user_id;

  v_label := coalesce(
    nullif(trim(v_accepter_display), ''),
    nullif(trim(v_accepter_username), ''),
    'Someone'
  );

  INSERT INTO public.notifications (user_id, type, title, body, payload)
  VALUES (
    NEW.user_id,
    'friend_accepted',
    v_label || ' accepted your friend request',
    NULL,
    jsonb_build_object(
      'friendship_id', NEW.id::text,
      'from_user_id', NEW.friend_user_id::text,
      'from_username', v_accepter_username
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS friendship_notify_accepted ON public.friendships;
CREATE TRIGGER friendship_notify_accepted
  AFTER UPDATE OF status ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_friend_request_accepted();

-- 3) Cancel pending request (DELETE) → remove matching unread friend_request notifications
CREATE OR REPLACE FUNCTION public.cleanup_friend_request_notifications()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  IF OLD.status = 'pending' THEN
    DELETE FROM public.notifications
    WHERE type = 'friend_request'
      AND (payload->>'friendship_id') = OLD.id::text;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS friendship_cleanup_request_notifications ON public.friendships;
CREATE TRIGGER friendship_cleanup_request_notifications
  AFTER DELETE ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.cleanup_friend_request_notifications();
