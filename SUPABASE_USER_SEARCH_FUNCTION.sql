-- Function: search_profiles_by_username
-- Purpose: Provide a safe, centralized way to search users by username.
-- Returns only non-sensitive fields (user_id, username, display_name) and
-- enforces a result limit for performance.

CREATE OR REPLACE FUNCTION search_profiles_by_username(p_query text)
RETURNS TABLE (
    user_id uuid,
    username text,
    display_name text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
    SELECT user_id, username, display_name
    FROM user_profiles
    WHERE username ILIKE '%' || p_query || '%'
    ORDER BY username
    LIMIT 20;
$$;

-- Grant execute permission to authenticated users only.
GRANT EXECUTE ON FUNCTION search_profiles_by_username(text) TO authenticated;
