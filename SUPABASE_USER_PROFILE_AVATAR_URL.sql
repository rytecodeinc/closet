-- Optional: public profile avatar URL for friend lists and search.
-- Run in Supabase SQL Editor, then redeploy RPCs below if you change return columns.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url text;

COMMENT ON COLUMN user_profiles.avatar_url IS 'HTTPS URL to a public or signed profile image (optional).';

-- Return type (OUT columns) cannot change with CREATE OR REPLACE; drop first.
DROP FUNCTION IF EXISTS public.get_friends();
DROP FUNCTION IF EXISTS public.search_profiles_by_username(text);

-- get_friends: include avatar_url
CREATE OR REPLACE FUNCTION get_friends()
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
    SELECT
      CASE
        WHEN f.user_id = auth.uid() THEN f.friend_user_id
        ELSE f.user_id
      END AS friend_id
    FROM friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id = auth.uid() OR f.friend_user_id = auth.uid())
  )
  SELECT up.user_id, up.username, up.display_name, up.avatar_url
  FROM user_profiles up
  JOIN accepted a ON a.friend_id = up.user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;

-- search_profiles_by_username: include avatar_url
CREATE OR REPLACE FUNCTION search_profiles_by_username(p_query text)
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
    SELECT user_id, username, display_name, avatar_url
    FROM user_profiles
    WHERE username ILIKE '%' || p_query || '%'
    ORDER BY username
    LIMIT 20;
$$;

GRANT EXECUTE ON FUNCTION search_profiles_by_username(text) TO authenticated;
