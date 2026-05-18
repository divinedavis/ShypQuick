-- ============================================================
-- Real delivery flow (customer side)
--
-- Until now the customer's tracking screen was a hardcoded local
-- animation (DeliverySimulation): 12s to "picked up", 20s to
-- "delivered", decoupled from what the driver actually did. The
-- driver's "Mark picked up" tap wrote nothing, and the customer
-- got no notification when a driver accepted.
--
-- This migration makes the flow real:
--   1. job_offers gains a `picked_up` status.
--   2. find_closest_online_driver only returns a driver who
--      actually serves the customer's pickup (radius + region) —
--      so a customer can't be matched with an out-of-range driver.
--   3. offer_driver_info() lets a customer fetch their assigned
--      driver's name + live location for their own offer.
--   4. A trigger pushes the customer an APNs notification whenever
--      their offer is accepted / picked up / delivered.
-- ============================================================

-- ── 1. picked_up status ─────────────────────────────────────
alter table public.job_offers drop constraint if exists job_offers_status_check;
alter table public.job_offers add constraint job_offers_status_check
  check (status in (
    'pending', 'accepted', 'picked_up',
    'declined', 'expired', 'delivered', 'cancelled'
  ));

-- ── 2. Customer matching honours the driver's radius + region ──
-- A customer must only ever match a driver who serves their pickup.
-- Reuses the dispatch gates: declared service region (no GPS needed)
-- plus travel radius once the driver's GPS has synced.
drop function if exists public.find_closest_online_driver(double precision, double precision);

create or replace function public.find_closest_online_driver(
  pickup_lat double precision,
  pickup_lng double precision,
  pickup_addr text default null
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
  left join public.driver_profiles dp on dp.id = dl.driver_id
  where dl.is_online = true
    and public.driver_serves_pickup_state(
          coalesce(dp.operating_states, '{}'), dp.state, pickup_addr)
    and (
      (dl.lat = 0 and dl.lng = 0)
      or public.miles_between(dl.lat, dl.lng, pickup_lat, pickup_lng)
           <= coalesce(dp.max_travel_radius_mi, 50)
    )
  order by
    power(dl.lat - pickup_lat, 2)
      + power((dl.lng - pickup_lng) * cos(radians(pickup_lat)), 2)
    asc
  limit 1
$$;

grant execute on function
  public.find_closest_online_driver(double precision, double precision, text)
  to authenticated;

-- ── 3. Customer-facing assigned-driver lookup ───────────────
-- Once a driver accepts, the customer needs the driver's name and
-- live location to render the tracking map. driver_locations RLS
-- hides drivers from customers, so this SECURITY DEFINER function
-- exposes exactly one driver's name + coords — and only for an
-- offer the calling customer owns.
create or replace function public.offer_driver_info(offer_id uuid)
returns table(
  driver_id uuid,
  full_name text,
  driver_lat double precision,
  driver_lng double precision,
  status text
)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select
    jo.driver_id,
    p.full_name,
    dl.lat as driver_lat,
    dl.lng as driver_lng,
    jo.status
  from public.job_offers jo
  left join public.driver_locations dl on dl.driver_id = jo.driver_id
  left join public.profiles p on p.id = jo.driver_id
  where jo.id = offer_id
    and jo.customer_id = auth.uid()
$$;

grant execute on function public.offer_driver_info(uuid) to authenticated;

-- ── 4. Notify the customer on every status change ───────────
-- Mirrors notify_new_offer(): posts the changed row to an edge
-- function (push-offer-status) which sends the customer an APNs
-- push. Fires only for the customer-meaningful transitions.
create or replace function public.notify_offer_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  webhook_secret text;
begin
  if new.status not in ('accepted', 'picked_up', 'delivered') then
    return new;
  end if;

  select decrypted_secret
    into webhook_secret
    from vault.decrypted_secrets
    where name = 'push_webhook_secret'
    limit 1;

  perform net.http_post(
    url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-offer-status',
    body    := jsonb_build_object('record', row_to_json(new)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-new-offer-secret', webhook_secret
    )
  );
  return new;
end;
$$;

drop trigger if exists on_job_offer_status_change on public.job_offers;
create trigger on_job_offer_status_change
  after update of status on public.job_offers
  for each row
  when (old.status is distinct from new.status)
  execute function public.notify_offer_status_change();
