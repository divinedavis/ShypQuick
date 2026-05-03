-- Fix infinite recursion in the RLS policies introduced by
-- 20260503000000_rls_tightening.sql. The cycle is:
--   profiles SELECT  -> exists in job_offers (RLS)
--   job_offers SELECT -> exists in profiles (RLS)
--
-- Postgres detects the loop and refuses to evaluate ("42P17"). We break it
-- by moving the cross-table lookups into SECURITY DEFINER helpers, which
-- bypass RLS on the referenced tables.
--
-- These helpers are STABLE so the planner can hoist them, and they pin
-- search_path to defeat function_search_path_mutable advisor warnings.

-- ============================================================
-- Helpers
-- ============================================================
create or replace function public.is_driver()
returns boolean
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('driver', 'both')
  )
$$;

create or replace function public.is_delivery_counterparty(other_user uuid)
returns boolean
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select exists (
    select 1 from public.deliveries d
    where (d.customer_id = auth.uid() and d.driver_id   = other_user)
       or (d.driver_id   = auth.uid() and d.customer_id = other_user)
  )
  or exists (
    select 1 from public.job_offers o
    where (o.customer_id = auth.uid() and o.driver_id   = other_user)
       or (o.driver_id   = auth.uid() and o.customer_id = other_user)
  )
$$;

create or replace function public.has_active_job_with_driver(d uuid)
returns boolean
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select exists (
    select 1 from public.job_offers o
    where o.driver_id   = d
      and o.customer_id = auth.uid()
      and o.status      = 'accepted'
  )
  or exists (
    select 1 from public.deliveries dx
    where dx.driver_id   = d
      and dx.customer_id = auth.uid()
      and dx.status      in ('accepted', 'picked_up')
  )
$$;

-- ============================================================
-- profiles: collapse to one helper-based policy
-- ============================================================
drop policy if exists "users view own profile" on public.profiles;
drop policy if exists "view profile of delivery counterparty" on public.profiles;
drop policy if exists "view profile of job_offer counterparty" on public.profiles;

create policy "users view self or counterparty profile"
  on public.profiles for select
  using (auth.uid() = id or public.is_delivery_counterparty(profiles.id));

-- ============================================================
-- job_offers: drivers visible via helper
-- ============================================================
drop policy if exists "drivers see pending unassigned offers" on public.job_offers;

create policy "drivers see pending unassigned offers"
  on public.job_offers for select
  using (
    status = 'pending'
    and driver_id is null
    and public.is_driver()
  );

-- ============================================================
-- driver_locations: customer visibility via helper
-- ============================================================
drop policy if exists "customer views assigned driver location" on public.driver_locations;

create policy "customer views assigned driver location"
  on public.driver_locations for select
  using (public.has_active_job_with_driver(driver_locations.driver_id));

-- ============================================================
-- storage.objects (item-photos): use is_driver() helper to avoid
-- recursing into profiles RLS during a storage read.
-- ============================================================
drop policy if exists "item-photos: drivers can read pending offer photos" on storage.objects;

create policy "item-photos: drivers can read pending offer photos"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and public.is_driver()
    and exists (
      select 1 from public.job_offers o
      where o.status     = 'pending'
        and o.driver_id  is null
        and o.photo_url  is not null
        and o.photo_url like '%' || name || '%'
    )
  );
