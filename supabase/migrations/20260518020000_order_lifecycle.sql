-- ============================================================
-- Order lifecycle: keep-looking queue, surge pricing, upgrade
-- consent.
--
-- #3  A pending offer used to die the moment one driver's offer
--     card timed out (or that driver declined). It should instead
--     stay queued until a driver ACCEPTS, and keep being offered
--     to local drivers. The Swift side stops writing declined/
--     expired; this side adds a sweeper that re-broadcasts.
-- #4  If an offer sits unaccepted, its price surges +$5 every
--     5 minutes (cap +$30) to attract a driver. The customer is
--     shown these terms before posting.
-- #2  A driver's Car→Truck upgrade is now a PROPOSAL: the price
--     change waits for the customer to approve it.
-- ============================================================

-- ── Columns ─────────────────────────────────────────────────
alter table public.job_offers
  -- #4 surge: accumulated surge already folded into total_cents,
  -- plus when it was last bumped (to pace one step per 5 min).
  add column if not exists surge_cents   integer not null default 0,
  add column if not exists last_surge_at timestamptz,
  -- #2 upgrade proposal: non-null total => awaiting customer OK.
  add column if not exists proposed_total_cents integer,
  add column if not exists proposed_at          timestamptz;

-- ── #2  upgrade_offer_to_truck → PROPOSE, don't apply ───────
-- The driver's tap now records a proposed price and pings the
-- customer; the change only lands once the customer approves via
-- respond_to_offer_upgrade().
create or replace function public.upgrade_offer_to_truck(p_offer_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_offer        public.job_offers%rowtype;
  v_old_total    int;
  v_new_total    int;
  v_fresh        public.job_offers%rowtype;
  webhook_secret text;
  c_car_base     constant int := 4000;
  c_truck_base   constant int := 15000;
begin
  select * into v_offer from public.job_offers where id = p_offer_id;
  if not found then
    raise exception 'offer % not found', p_offer_id using errcode = '42704';
  end if;
  if v_offer.driver_id is null or v_offer.driver_id <> auth.uid() then
    raise exception 'only the assigned driver can upgrade this offer'
      using errcode = '42501';
  end if;
  if v_offer.status not in ('accepted', 'picked_up') then
    raise exception 'offer must be accepted to upgrade (got %)', v_offer.status
      using errcode = '22023';
  end if;
  if v_offer.vehicle_type = 'truck' then
    raise exception 'offer is already a truck job' using errcode = '22023';
  end if;
  if v_offer.proposed_total_cents is not null then
    raise exception 'an upgrade is already awaiting the customer'
      using errcode = '22023';
  end if;

  v_old_total := v_offer.total_cents;
  v_new_total := v_old_total - c_car_base + c_truck_base;

  -- Record the proposal only — total_cents/vehicle stay unchanged
  -- until the customer approves.
  update public.job_offers
     set proposed_total_cents = v_new_total,
         proposed_at          = now()
   where id = p_offer_id;

  -- Notify the customer (push-offer-status detects proposed_total_cents).
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;
  select * into v_fresh from public.job_offers where id = p_offer_id;
  perform net.http_post(
    url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-offer-status',
    body    := jsonb_build_object('record', row_to_json(v_fresh)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-new-offer-secret', webhook_secret
    )
  );

  return json_build_object(
    'old_total_cents',  v_old_total,
    'new_total_cents',  v_new_total,
    'difference_cents', v_new_total - v_old_total,
    'status',           'proposed'
  );
end $$;

grant execute on function public.upgrade_offer_to_truck(uuid) to authenticated;

-- ── #2  respond_to_offer_upgrade: customer approves / declines ─
create or replace function public.respond_to_offer_upgrade(
  p_offer_id uuid,
  p_approve  boolean
)
returns json
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_offer public.job_offers%rowtype;
begin
  select * into v_offer from public.job_offers where id = p_offer_id;
  if not found then
    raise exception 'offer % not found', p_offer_id using errcode = '42704';
  end if;
  if v_offer.customer_id <> auth.uid() then
    raise exception 'only the customer can respond to this upgrade'
      using errcode = '42501';
  end if;
  if v_offer.proposed_total_cents is null then
    raise exception 'no upgrade is awaiting approval' using errcode = '22023';
  end if;

  if p_approve then
    update public.job_offers
       set total_cents          = v_offer.proposed_total_cents,
           vehicle_type         = 'truck',
           size                 = 'large',
           category_title       = 'Truck',
           category_icon        = 'truck.box.fill',
           proposed_total_cents = null,
           proposed_at          = null
     where id = p_offer_id;
  else
    update public.job_offers
       set proposed_total_cents = null,
           proposed_at          = null
     where id = p_offer_id;
  end if;

  return json_build_object('approved', p_approve);
end $$;

grant execute on function public.respond_to_offer_upgrade(uuid, boolean) to authenticated;

-- ── offer_driver_info: also expose price + pending upgrade ──
drop function if exists public.offer_driver_info(uuid);
create or replace function public.offer_driver_info(offer_id uuid)
returns table(
  driver_id            uuid,
  full_name            text,
  driver_lat           double precision,
  driver_lng           double precision,
  status               text,
  total_cents          integer,
  proposed_total_cents integer
)
language sql
security definer
set search_path = public, pg_catalog
stable
as $$
  select
    jo.driver_id,
    p.full_name,
    dl.lat  as driver_lat,
    dl.lng  as driver_lng,
    jo.status,
    jo.total_cents,
    jo.proposed_total_cents
  from public.job_offers jo
  left join public.driver_locations dl on dl.driver_id = jo.driver_id
  left join public.profiles p          on p.id        = jo.driver_id
  where jo.id = offer_id
    and jo.customer_id = auth.uid()
$$;

grant execute on function public.offer_driver_info(uuid) to authenticated;

-- ── #3 + #4  sweep_pending_offers: surge + keep-looking ─────
-- Runs on a cron. For every offer still pending after 5 minutes:
--   • surge total_cents by $5 (once per 5 min, capped at +$30)
--   • re-broadcast to eligible online drivers via push-new-offer
-- so the offer keeps hunting a local driver until it's accepted.
create or replace function public.sweep_pending_offers()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_id           uuid;
  v_fresh        public.job_offers%rowtype;
  webhook_secret text;
  c_step constant int := 500;   -- +$5
  c_cap  constant int := 3000;  -- +$30
begin
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  for v_id in
    select id from public.job_offers
    where status = 'pending'
      and driver_id is null
      and created_at < now() - interval '5 minutes'
  loop
    -- #4 surge — one step per 5 min, until the cap.
    update public.job_offers
       set total_cents   = total_cents + c_step,
           surge_cents   = surge_cents + c_step,
           last_surge_at = now()
     where id = v_id
       and surge_cents < c_cap
       and coalesce(last_surge_at, created_at) < now() - interval '5 minutes';

    -- #3 re-broadcast the (possibly surged) offer to local drivers.
    select * into v_fresh from public.job_offers where id = v_id;
    perform net.http_post(
      url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-new-offer',
      body    := jsonb_build_object('record', row_to_json(v_fresh)),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-new-offer-secret', webhook_secret
      )
    );
  end loop;
end $$;

-- ── Cron: sweep every 5 minutes ─────────────────────────────
select cron.schedule(
  'sweep-pending-offers',
  '*/5 * * * *',
  $$ select public.sweep_pending_offers(); $$
);
