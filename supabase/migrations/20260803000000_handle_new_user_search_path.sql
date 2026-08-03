-- Pin the search_path on handle_new_user.
--
-- This is the AFTER INSERT trigger on auth.users, so it runs as its owner on
-- every signup — the one definer function in this schema an unauthenticated
-- caller can reliably cause to execute. Without `set search_path`, the
-- unqualified `public.profiles` insert resolves against the search_path in
-- effect for the inserting session; anyone able to create objects in a schema
-- earlier on that path could shadow the target and capture the write with the
-- owner's privileges.
--
-- 20260613000000_harden_security_definer_grants.sql pinned the rest of the
-- definer functions; this one predates it (declared in 20260415000000 and
-- redeclared in 20260415120000) and was missed both times.
--
-- Body reproduced verbatim from 20260415120000_role_on_signup.sql — the only
-- changes are the `set search_path` clause and qualifying the metadata reads.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  meta_role text;
begin
  meta_role := new.raw_user_meta_data->>'role';
  if meta_role is null or meta_role not in ('customer', 'driver', 'both') then
    meta_role := 'customer';
  end if;

  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    meta_role
  );
  return new;
end;
$$;
