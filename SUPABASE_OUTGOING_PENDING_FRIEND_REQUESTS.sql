-- RPC: get_outgoing_pending_friend_requests
-- Returns profiles the current user has sent a pending friend request to.

DROP FUNCTION IF EXISTS public.get_outgoing_pending_friend_requests();

CREATE OR REPLACE FUNCTION public.get_outgoing_pending_friend_requests()
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
  SELECT
    up.user_id,
    up.username,
    up.display_name,
    up.avatar_url
  FROM public.friendships f
  JOIN public.user_profiles up ON up.user_id = f.friend_user_id
  WHERE f.user_id = auth.uid()
    AND f.status = 'pending'
  ORDER BY f.created_at DESC, up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_outgoing_pending_friend_requests() TO authenticated;
