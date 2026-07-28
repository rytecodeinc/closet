-- Notify content owners when someone likes their item or outfit.
-- Requires: content_likes, notifications, user_profiles, items, outfits, item_photos.
-- Run after SUPABASE_CONTENT_LIKES.sql and SUPABASE_NOTIFICATIONS_TABLE.sql.
-- Push delivery uses the existing notifications INSERT webhook / send-push function.

-- 1) Like created → notify owner (includes thumbnail URL in payload)
CREATE OR REPLACE FUNCTION public.notify_content_like_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
DECLARE
  v_owner uuid;
  v_content_name text;
  v_image_url text;
  v_liker_username text;
  v_liker_display text;
  v_label text;
  v_noun text;
BEGIN
  IF NEW.target_type = 'item' THEN
    SELECT
      i.user_id,
      i.name,
      COALESCE(
        (
          SELECT COALESCE(p.thumbnail_url, p.image_url)
          FROM public.item_photos p
          WHERE p.item_id = i.id
            AND COALESCE(p.is_primary, false) = true
          ORDER BY p.created_at NULLS LAST
          LIMIT 1
        ),
        (
          SELECT COALESCE(p.thumbnail_url, p.image_url)
          FROM public.item_photos p
          WHERE p.item_id = i.id
          ORDER BY COALESCE(p.is_primary, false) DESC, p.created_at NULLS LAST
          LIMIT 1
        )
      )
    INTO v_owner, v_content_name, v_image_url
    FROM public.items i
    WHERE i.id = NEW.target_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false;
    v_noun := 'item';
  ELSIF NEW.target_type = 'outfit' THEN
    SELECT o.user_id, o.name, o.image_url
    INTO v_owner, v_content_name, v_image_url
    FROM public.outfits o
    WHERE o.id = NEW.target_id
      AND COALESCE(o.is_soft_deleted, false) = false
      AND COALESCE(o.is_draft, false) = false;
    v_noun := 'outfit';
  ELSE
    RETURN NEW;
  END IF;

  -- Missing / soft-deleted content, or self-like (should already be blocked by toggle RPC).
  IF v_owner IS NULL OR v_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Idempotent: one notification per content_likes row.
  IF EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.type = 'content_like'
      AND (n.payload->>'content_like_id') = NEW.id::text
  ) THEN
    RETURN NEW;
  END IF;

  SELECT up.username, up.display_name
  INTO v_liker_username, v_liker_display
  FROM public.user_profiles up
  WHERE up.user_id = NEW.user_id;

  v_label := coalesce(
    nullif(trim(v_liker_display), ''),
    nullif(trim(v_liker_username), ''),
    'Someone'
  );

  INSERT INTO public.notifications (user_id, type, title, body, payload)
  VALUES (
    v_owner,
    'content_like',
    v_label || ' liked your ' || v_noun,
    nullif(trim(coalesce(v_content_name, '')), ''),
    jsonb_build_object(
      'content_like_id', NEW.id::text,
      'from_user_id', NEW.user_id::text,
      'from_username', v_liker_username,
      'target_type', NEW.target_type,
      'target_id', NEW.target_id::text,
      'image_url', v_image_url
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS content_like_notify_owner ON public.content_likes;
CREATE TRIGGER content_like_notify_owner
  AFTER INSERT ON public.content_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_content_like_created();

-- 2) Unlike → remove matching unread-or-any notification for that like
CREATE OR REPLACE FUNCTION public.cleanup_content_like_notifications()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  DELETE FROM public.notifications
  WHERE type = 'content_like'
    AND (payload->>'content_like_id') = OLD.id::text;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS content_like_cleanup_notifications ON public.content_likes;
CREATE TRIGGER content_like_cleanup_notifications
  AFTER DELETE ON public.content_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.cleanup_content_like_notifications();
