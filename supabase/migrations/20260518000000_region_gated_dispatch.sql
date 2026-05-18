-- ============================================================
-- Region-gated dispatch
--
-- The radius filter needs the driver's live GPS in driver_locations.
-- In practice that location never reliably synced — every row stayed
-- at 0,0 — so the radius gate fails open and a driver in SC kept
-- getting pickups in NY.
--
-- Fix: gate offers on the driver's DECLARED service region too. Every
-- driver enters their state / operating_states / primary service area
-- at onboarding (driver_profiles), and every pickup address carries
-- its state ("475 Alabama Ave, Brooklyn, NY, United States"). Comparing
-- those needs no GPS at all and works the instant this deploys.
--
-- Eligibility now = region gate AND radius gate:
--   * region gate — the pickup's state must be one the driver declared
--     (skipped only when the address has no parseable state, or the
--     driver declared no region at all).
--   * radius gate — once real GPS has synced, the pickup must also be
--     within max_travel_radius_mi; still fails open while lat/lng = 0,0.
-- ============================================================

-- ------------------------------------------------------------
-- pickup_state: the 2-letter state code from a pickup address.
-- The app's geocoder is inconsistent — it emits both ", NY," and
-- ", Elgin SC" (no comma before the state) — so the separator may be
-- a comma or a space. Tolerates a trailing ZIP and an optional
-- ", United States" suffix. Returns NULL when no state can be parsed.
-- ------------------------------------------------------------
create or replace function public.pickup_state(address text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select upper(substring(
    address from
    '[,\s]\s*([A-Za-z]{2})(?:\s+\d{5}(?:-\d{4})?)?\s*(?:,?\s*United States)?\s*$'
  ))
$$;

-- ------------------------------------------------------------
-- driver_serves_pickup_state: true when the pickup's state is one the
-- driver operates in. Fails open (true) when the address has no
-- parseable state, or the driver declared neither operating_states nor
-- a home state — so missing data never silently blocks dispatch.
-- Comparison is case-insensitive ("Sc" vs "SC").
-- ------------------------------------------------------------
create or replace function public.driver_serves_pickup_state(
  operating_states text[],
  driver_state text,
  pickup_addr text
)
returns boolean
language sql
immutable
parallel safe
set search_path = public, pg_catalog
as $$
  select case
    when public.pickup_state(pickup_addr) is null then true
    when coalesce(array_length(operating_states, 1), 0) = 0
         and nullif(trim(coalesce(driver_state, '')), '') is null then true
    else
      upper(trim(coalesce(driver_state, ''))) = public.pickup_state(pickup_addr)
      or exists (
        select 1 from unnest(operating_states) s
        where upper(trim(s)) = public.pickup_state(pickup_addr)
      )
  end
$$;

-- ------------------------------------------------------------
-- online_drivers_for_offer: online drivers eligible for a pickup.
-- Gains a pickup_addr argument for the region gate (defaulted so old
-- callers keep working). Replaces the lat/lng-only version.
-- ------------------------------------------------------------
drop function if exists public.online_drivers_for_offer(double precision, double precision);

create or replace function public.online_drivers_for_offer(
  pickup_lat double precision,
  pickup_lng double precision,
  pickup_addr text default null
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
    -- region gate: pickup's state must be one the driver declared
    and public.driver_serves_pickup_state(
          coalesce(dp.operating_states, '{}'), dp.state, pickup_addr)
    -- radius gate: precise once GPS has synced; fails open at 0,0
    and (
      (dl.lat = 0 and dl.lng = 0)
      or public.miles_between(dl.lat, dl.lng, pickup_lat, pickup_lng)
           <= coalesce(dp.max_travel_radius_mi, 50)
    )
$$;

grant execute on function
  public.online_drivers_for_offer(double precision, double precision, text)
  to service_role, authenticated;

-- ------------------------------------------------------------
-- Apply both gates to the driver SELECT policy on job_offers so an
-- out-of-region / out-of-radius offer is never even queryable.
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
        and public.driver_serves_pickup_state(
              coalesce(dp.operating_states, '{}'), dp.state,
              job_offers.pickup_address)
        and (
          (dl.lat = 0 and dl.lng = 0)
          or public.miles_between(dl.lat, dl.lng,
                                  job_offers.pickup_lat, job_offers.pickup_lng)
               <= coalesce(dp.max_travel_radius_mi, 50)
        )
    )
  );
