-- RPC: friends list for any user (mutual accepted edges → distinct profiles).
-- Own-user list remains get_friends(); this powers Profile > Friends and other-user friends.
-- Run in Supabase SQL Editor after SUPABASE_USER_FOLLOW_COUNTS.sql (or alongside).

DROP FUNCTION IF EXISTS public.get_user_friends_profiles(uuid);

CREATE OR REPLACE FUNCTION public.get_user_friends_profiles(p_user_id uuid)
RETURNS TABLE (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH accepted AS (
    SELECT DISTINCT
      CASE
        WHEN f.user_id = p_user_id THEN f.friend_user_id
        ELSE f.user_id
      END AS friend_id
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id = p_user_id OR f.friend_user_id = p_user_id)
  )
  SELECT up.user_id, up.username, up.display_name, up.avatar_url
  FROM public.user_profiles up
  JOIN accepted a ON a.friend_id = up.user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_friends_profiles(uuid) TO authenticated;
