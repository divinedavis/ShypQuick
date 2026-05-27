-- Lock down public.spatial_ref_sys against API writes.
--
-- The Supabase security advisor flagged rls_disabled_in_public on this PostGIS
-- table. The earlier 20260422 migration noted that RLS / REVOKE wouldn't take
-- effect because the table is owned by supabase_admin. That note was wrong
-- about the real exposure: information_schema.role_table_grants shows that
-- anon and authenticated retain INSERT/UPDATE/DELETE/TRUNCATE, and PostgREST
-- happily honors them (verified: anon could DELETE rows via /rest/v1).
--
-- We can't ALTER or REVOKE without owning the table, but the postgres role
-- does hold TRIGGER privilege on it, so we attach a BEFORE-trigger that
-- raises on any write. PostGIS only ever reads spatial_ref_sys at query time,
-- so blocking writes doesn't affect ST_Transform / geography casts / etc.

create or replace function public.block_spatial_ref_sys_write()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  raise exception
    'public.spatial_ref_sys is a PostGIS-managed reference table and is read-only via the API'
    using errcode = '42501';
end;
$$;

drop trigger if exists block_spatial_ref_sys_writes on public.spatial_ref_sys;
create trigger block_spatial_ref_sys_writes
  before insert or update or delete on public.spatial_ref_sys
  for each row execute function public.block_spatial_ref_sys_write();

drop trigger if exists block_spatial_ref_sys_truncate on public.spatial_ref_sys;
create trigger block_spatial_ref_sys_truncate
  before truncate on public.spatial_ref_sys
  for each statement execute function public.block_spatial_ref_sys_write();
