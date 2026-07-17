-- Mutual friendships as bidirectional accepted edges + directional follow counts.
-- following = accepted rows where the user is requester (user_id).
-- followers = accepted rows where the user is recipient (friend_user_id).
-- On accept, insert the reverse edge so both users get following + followers.
-- Run in Supabase SQL Editor after SUPABASE_FRIENDSHIPS_TABLE.sql.

-- 1) Directional counts (unchanged semantics; correct once reciprocal rows exist)
DROP FUNCTION IF EXISTS public.get_user_follow_counts(uuid);

CREATE OR REPLACE FUNCTION public.get_user_follow_counts(p_user_id uuid)
RETURNS TABLE (
  following_count integer,
  followers_count integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT
    (
      SELECT COUNT(*)::integer
      FROM public.friendships f
      WHERE f.status = 'accepted'
        AND f.user_id = p_user_id
    ) AS following_count,
    (
      SELECT COUNT(*)::integer
      FROM public.friendships f
      WHERE f.status = 'accepted'
        AND f.friend_user_id = p_user_id
    ) AS followers_count;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_follow_counts(uuid) TO authenticated;

-- 2) Unique friend count (distinct people, not sum of both edges)
DROP FUNCTION IF EXISTS public.get_user_friend_count(uuid);

CREATE OR REPLACE FUNCTION public.get_user_friend_count(p_user_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT COUNT(*)::integer
  FROM (
    SELECT DISTINCT
      CASE
        WHEN f.user_id = p_user_id THEN f.friend_user_id
        ELSE f.user_id
      END AS friend_id
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id = p_user_id OR f.friend_user_id = p_user_id)
  ) friends;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_friend_count(uuid) TO authenticated;

-- 3) On accept, ensure reciprocal accepted edge (B→A when A→B is accepted)
CREATE OR REPLACE FUNCTION public.ensure_reciprocal_friendship_on_accept()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS
$$
BEGIN
  IF NOT (OLD.status = 'pending' AND NEW.status = 'accepted') THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.friendships (user_id, friend_user_id, status)
  VALUES (NEW.friend_user_id, NEW.user_id, 'accepted')
  ON CONFLICT (user_id, friend_user_id)
  DO UPDATE SET
    status = 'accepted',
    updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS friendship_ensure_reciprocal_on_accept ON public.friendships;
CREATE TRIGGER friendship_ensure_reciprocal_on_accept
  AFTER UPDATE OF status ON public.friendships
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_reciprocal_friendship_on_accept();

-- 4) Backfill missing reverse edges for already-accepted friendships
INSERT INTO public.friendships (user_id, friend_user_id, status)
SELECT f.friend_user_id, f.user_id, 'accepted'
FROM public.friendships f
WHERE f.status = 'accepted'
  AND f.user_id <> f.friend_user_id
  AND NOT EXISTS (
    SELECT 1
    FROM public.friendships r
    WHERE r.user_id = f.friend_user_id
      AND r.friend_user_id = f.user_id
  );

-- 5) get_friends: DISTINCT so reciprocal edges don't duplicate list rows
DROP FUNCTION IF EXISTS public.get_friends();

CREATE OR REPLACE FUNCTION public.get_friends()
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
        WHEN f.user_id = auth.uid() THEN f.friend_user_id
        ELSE f.user_id
      END AS friend_id
    FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (f.user_id = auth.uid() OR f.friend_user_id = auth.uid())
  )
  SELECT up.user_id, up.username, up.display_name, up.avatar_url
  FROM public.user_profiles up
  JOIN accepted a ON a.friend_id = up.user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_friends() TO authenticated;

-- 6) Directional profile lists used by Profile > Following / Followers
DROP FUNCTION IF EXISTS public.get_user_following_profiles(uuid);

CREATE OR REPLACE FUNCTION public.get_user_following_profiles(p_user_id uuid)
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
  SELECT DISTINCT
    up.user_id,
    up.username,
    up.display_name,
    up.avatar_url
  FROM public.friendships f
  JOIN public.user_profiles up ON up.user_id = f.friend_user_id
  WHERE f.status = 'accepted'
    AND f.user_id = p_user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_following_profiles(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.get_user_follower_profiles(uuid);

CREATE OR REPLACE FUNCTION public.get_user_follower_profiles(p_user_id uuid)
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
  SELECT DISTINCT
    up.user_id,
    up.username,
    up.display_name,
    up.avatar_url
  FROM public.friendships f
  JOIN public.user_profiles up ON up.user_id = f.user_id
  WHERE f.status = 'accepted'
    AND f.friend_user_id = p_user_id
  ORDER BY up.username;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_follower_profiles(uuid) TO authenticated;
