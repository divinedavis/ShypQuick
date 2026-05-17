-- ============================================================
-- Radius-filtered dispatch
--
-- Bug: a driver in SC received a NY job offer 593 mi away even
-- though he set a `max_travel_radius_mi` preference. Nothing in
-- the dispatch pipeline ever compared the offer's pickup against
-- the driver's radius:
--   * push-new-offer edge function pushed to ALL online drivers
--   * the job_offers SELECT policy filtered only by role
--
-- This migration adds the missing distance check in two places
-- (defense in depth):
--   1. miles_between() — a cheap equirectangular distance helper.
--   2. online_drivers_for_offer() — used by the edge function to
--      pick which online drivers to notify.
--   3. The "drivers see pending unassigned offers" RLS policy now
--      also requires the driver to be within their radius, so an
--      out-of-range offer can't even be queried.
--
-- Drivers with no radius set (NULL) fall back to a 50-mi cap so a
-- missing preference no longer means "the whole country".
-- ============================================================

-- ------------------------------------------------------------
-- Distance helper. Equirectangular approximation (≈69 mi per
-- degree of latitude) — accurate enough for the local radii this
-- app matches over, and IMMUTABLE so it's cheap inside RLS.
-- ------------------------------------------------------------
create or replace function public.miles_between(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
)
returns double precision
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select 69.0 * sqrt(
    power(lat1 - lat2, 2)
    + power((lng1 - lng2) * cos(radians(lat2)), 2)
  )
$$;

-- ------------------------------------------------------------
-- online_drivers_for_offer: online drivers whose stored location
-- is within their travel radius of the pickup. Called by the
-- push-new-offer edge function (service_role) to decide who to
-- notify. SECURITY DEFINER so it can read every driver_locations
-- row regardless of the caller's RLS.
-- ------------------------------------------------------------
create or replace function public.online_drivers_for_offer(
  pickup_lat double precision,
  pickup_lng double precision
)
returns table(driver_id uuid)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select dl.driver_id
  from public.driver_locations dl
  left join public.driver_profiles dp on dp.id = dl.driver_id
  where dl.is_online = true
    and public.miles_between(dl.lat, dl.lng, pickup_lat, pickup_lng)
        <= coalesce(dp.max_travel_radius_mi, 50)
$$;

grant execute on function public.online_drivers_for_offer(double precision, double precision)
  to service_role, authenticated;

-- ------------------------------------------------------------
-- Tighten the driver SELECT policy on job_offers so an offer
-- outside a driver's radius is not even visible to them. This
-- backs up the edge-function filter: if a push slips through, or
-- the driver polls fetchPendingOffers() directly, RLS still hides
-- the row.
-- ------------------------------------------------------------
drop policy if exists "drivers see pending unassigned offers" on public.job_offers;
create policy "drivers see pending unassigned offers"
  on public.job_offers for select
  using (
    status = 'pending'
    and driver_id is null
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('driver', 'both')
    )
    and exists (
      select 1
      from public.driver_locations dl
      left join public.driver_profiles dp on dp.id = dl.driver_id
      where dl.driver_id = auth.uid()
        and public.miles_between(dl.lat, dl.lng,
                                 job_offers.pickup_lat, job_offers.pickup_lng)
            <= coalesce(dp.max_travel_radius_mi, 50)
    )
  );
