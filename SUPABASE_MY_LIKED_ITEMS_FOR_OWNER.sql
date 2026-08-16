-- Item IDs the caller has liked that belong to another user (other-user profile Likes filter).
-- Requires: content_likes, items.

CREATE OR REPLACE FUNCTION public.get_my_liked_item_ids_for_owner(p_owner_id uuid)
RETURNS TABLE (item_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public AS
$$
  SELECT cl.target_id
  FROM public.content_likes cl
  INNER JOIN public.items i ON i.id = cl.target_id
  WHERE cl.user_id = auth.uid()
    AND cl.target_type = 'item'
    AND i.user_id = p_owner_id
    AND COALESCE(i.is_soft_deleted, false) = false
    AND COALESCE(i.is_draft, false) = false;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_liked_item_ids_for_owner(uuid) TO authenticated;
