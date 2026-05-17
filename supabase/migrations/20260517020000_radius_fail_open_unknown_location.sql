-- ============================================================
-- Radius matching: fail OPEN when a driver's location is unknown
--
-- The radius filter (20260517000000) compares driver_locations
-- against the pickup. But until the app fix that syncs real GPS
-- ships and every driver re-goes-online on the new build, every
-- existing driver_locations row is still 0,0. With a strict
-- filter that means 0,0 is thousands of miles from every real
-- pickup, so EVERY driver is excluded from EVERY offer — i.e.
-- dispatch silently stops for the whole app.
--
-- Fix: treat lat = 0 AND lng = 0 as "location unknown" and fail
-- open — such a driver is still eligible. Only a driver with a
-- real, known location that is genuinely outside their radius is
-- filtered out. Once a driver runs the new build and goes online,
-- their coordinates become real and the radius applies normally.
-- ============================================================

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
    and (
      -- location unknown (never synced) → fail open, stay eligible
      (dl.lat = 0 and dl.lng = 0)
      -- known location → must be within the driver's travel radius
      or public.miles_between(dl.lat, dl.lng, pickup_lat, pickup_lng)
           <= coalesce(dp.max_travel_radius_mi, 50)
    )
$$;

grant execute on function public.online_drivers_for_offer(double precision, double precision)
  to service_role, authenticated;

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
        and (
          (dl.lat = 0 and dl.lng = 0)
          or public.miles_between(dl.lat, dl.lng,
                                  job_offers.pickup_lat, job_offers.pickup_lng)
               <= coalesce(dp.max_travel_radius_mi, 50)
        )
    )
  );
