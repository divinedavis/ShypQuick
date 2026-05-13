-- ============================================================
-- Pre-emptive Data API grants (Supabase Oct 30 2026 deadline)
--
-- Supabase announced (email 2026-05-13) that on October 30, 2026
-- the implicit public-schema grants PostgREST relies on will be
-- removed for ALL existing projects. After that date a table
-- without an explicit `grant ... to anon|authenticated` returns
-- 42501 from the Data API.
--
-- This migration walks pg_tables / pg_views in `public` and
-- writes the right grants for everything that exists today.
-- Dynamic-SQL form so it works on any schema:
--   anon          → SELECT (RLS-enabled tables only, so a non-RLS
--                   table stays non-public by default)
--   authenticated → SELECT, INSERT, UPDATE, DELETE
--   service_role  → ALL
--   views         → SELECT to anon + authenticated
-- ============================================================

do $$
declare
  rec record;
begin
  for rec in
    select t.tablename, c.relrowsecurity as rls_on
    from pg_tables t
    join pg_class c on c.relname = t.tablename and c.relnamespace = 'public'::regnamespace
    where t.schemaname = 'public'
  loop
    if rec.rls_on then
      execute format('grant select on public.%I to anon', rec.tablename);
    end if;
    execute format('grant select, insert, update, delete on public.%I to authenticated', rec.tablename);
    execute format('grant all on public.%I to service_role', rec.tablename);
  end loop;
  for rec in select viewname from pg_views where schemaname = 'public' loop
    execute format('grant select on public.%I to anon, authenticated', rec.viewname);
  end loop;
end $$;
