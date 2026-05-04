-- Customer-side driver matching helper.
--
-- The customer's UI runs a fake-driver animation while their job_offer is
-- broadcast to drivers via APNs. To position the animation it needs the
-- closest online driver's lat/lng + name, but the new driver_locations RLS
-- (intentionally) hides every driver from customers until they've accepted
-- the job. Without a workaround the customer always saw
-- "No drivers online nearby" even when drivers were active.
--
-- This SECURITY DEFINER function exposes only the single closest match
-- (name + coordinates) for animation purposes — not the full driver roster.
-- Equirectangular distance is fine for the small radii this matches over;
-- avoids the postgis / cube + earthdistance dependency.

create or replace function public.find_closest_online_driver(
  pickup_lat double precision,
  pickup_lng double precision
)
returns table(
  driver_id uuid,
  full_name text,
  driver_lat double precision,
  driver_lng double precision
)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select
    dl.driver_id,
    p.full_name,
    dl.lat as driver_lat,
    dl.lng as driver_lng
  from public.driver_locations dl
  left join public.profiles p on p.id = dl.driver_id
  where dl.is_online = true
  order by
    power(dl.lat - pickup_lat, 2)
      + power((dl.lng - pickup_lng) * cos(radians(pickup_lat)), 2)
    asc
  limit 1
$$;

grant execute on function public.find_closest_online_driver(double precision, double precision)
  to authenticated;
