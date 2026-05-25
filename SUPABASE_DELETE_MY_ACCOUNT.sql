-- Run in Supabase SQL Editor. Lets the iOS app call `delete_my_account` via RPC after sign-in.
-- Extend the DELETE statements as you add synced tables in production.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.user_profiles where user_id = uid;

  -- Add further user-scoped table deletes here (items, outfits, wardrobes, etc.).

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
