-- Supabase advisor lint fixes: function_search_path_mutable on trigger functions.
--
-- NOTE on rls_disabled_in_public / public.spatial_ref_sys:
-- This is PostGIS's coordinate-system reference table, owned by supabase_admin.
-- Neither ENABLE ROW LEVEL SECURITY nor REVOKE takes effect from the postgres
-- role. The earlier guidance to dismiss the warning was wrong: anon and
-- authenticated retain INSERT/UPDATE/DELETE/TRUNCATE through PostgREST, so
-- the table was genuinely exposed. See 20260527000000_block_spatial_ref_sys_writes.sql
-- for the actual fix (BEFORE-trigger that raises on writes).

-- ============================================================
-- handle_new_user: pin search_path (preserves current role logic)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
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
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ============================================================
-- notify_new_offer: pin search_path (net.http_post needs pg_net reachable)
-- ============================================================
create or replace function public.notify_new_offer()
returns trigger
language plpgsql
security definer
set search_path = public, net, pg_catalog
as $$
begin
  perform net.http_post(
    url := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-new-offer',
    body := jsonb_build_object('record', row_to_json(new)),
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer sb_publishable_rL9NCr_DbYqvne-qaJIUQQ_N2il35jy"}'::jsonb
  );
  return new;
end;
$$;
