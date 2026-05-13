-- RPC: get_friends
-- Returns the current user's accepted friends (public profile fields only).

CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
  user_id uuid,
  username text,
  display_name text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  WITH accepted AS (
    SELECT
      CASE
        WHEN f.user_id = auth.uid() THEN f.friend_user_id
        ELSE f.user_id
      END AS friend_id
    FROM friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id = auth.uid() OR f.friend_user_id = auth.uid())
  )
  SELECT up.user_id, up.username, up.display_name
  FROM user_profiles up
  JOIN accepted a ON a.friend_id = up.user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;
