-- Share item/outfit with a friend → recipient notification.
-- Requires: notifications, friendships, user_profiles, items, outfits, item_photos.
-- Run in Supabase SQL Editor.

DROP FUNCTION IF EXISTS public.share_content_with_friend(uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.share_content_with_friend(
  p_recipient_id uuid,
  p_target_type text,
  p_target_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender uuid := auth.uid();
  v_owner uuid;
  v_content_name text;
  v_image_url text;
  v_sender_username text;
  v_sender_display text;
  v_label text;
  v_noun text;
  v_notification_id uuid;
BEGIN
  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_recipient_id IS NULL OR p_target_id IS NULL THEN
    RAISE EXCEPTION 'Missing recipient or content id';
  END IF;

  IF p_recipient_id = v_sender THEN
    RAISE EXCEPTION 'Cannot share with yourself';
  END IF;

  IF p_target_type NOT IN ('item', 'outfit') THEN
    RAISE EXCEPTION 'Invalid target type';
  END IF;

  -- Must be accepted friends (either direction).
  IF NOT EXISTS (
    SELECT 1
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (
        (f.user_id = v_sender AND f.friend_user_id = p_recipient_id)
        OR (f.user_id = p_recipient_id AND f.friend_user_id = v_sender)
      )
  ) THEN
    RAISE EXCEPTION 'Recipient is not an accepted friend';
  END IF;

  IF p_target_type = 'item' THEN
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
    WHERE i.id = p_target_id
      AND COALESCE(i.is_soft_deleted, false) = false
      AND COALESCE(i.is_draft, false) = false;
    v_noun := 'item';
  ELSE
    SELECT o.user_id, o.name, o.image_url
    INTO v_owner, v_content_name, v_image_url
    FROM public.outfits o
    WHERE o.id = p_target_id
      AND COALESCE(o.is_soft_deleted, false) = false
      AND COALESCE(o.is_draft, false) = false;
    v_noun := 'outfit';
  END IF;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Content not found';
  END IF;

  IF v_owner <> v_sender THEN
    RAISE EXCEPTION 'You can only share your own content';
  END IF;

  SELECT up.username, up.display_name
  INTO v_sender_username, v_sender_display
  FROM public.user_profiles up
  WHERE up.user_id = v_sender;

  v_label := coalesce(
    nullif(trim(v_sender_display), ''),
    nullif(trim(v_sender_username), ''),
    'Someone'
  );

  INSERT INTO public.notifications (user_id, type, title, body, payload)
  VALUES (
    p_recipient_id,
    'content_share',
    v_label || ' shared an ' || v_noun || ' with you',
    nullif(trim(coalesce(v_content_name, '')), ''),
    jsonb_build_object(
      'from_user_id', v_sender::text,
      'from_username', v_sender_username,
      'target_type', p_target_type,
      'target_id', p_target_id::text,
      'image_url', v_image_url
    )
  )
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.share_content_with_friend(uuid, text, uuid) TO authenticated;
