-- ============================================================
-- Server-authoritative pricing + payment_status pinning
--
-- VULNERABILITY (HIGH — payment tampering / "set your own price")
--   job_offers.total_cents and authorized_amount_cents were computed
--   entirely on-device (ShypQuick/Services/PricingService.swift) and
--   written straight into the table. RLS only checked
--   `auth.uid() = customer_id`, so a customer could insert a row with
--   total_cents = 1 (or any value) and get a real delivery for a penny.
--   The free flow (no Stripe PI) is charged purely off total_cents, and
--   the paid flow captures least(total_cents, authorized_amount_cents),
--   so a tampered low total directly undercharges.
--
-- VULNERABILITY (MEDIUM — payment_status forgery)
--   DispatchService.swift writes payment_status directly, and the
--   authenticated role holds column UPDATE/INSERT on payment_status, so a
--   client could self-assign 'authorized' (or advance toward 'captured')
--   without an actual Stripe authorization.
--
-- FIX (overwrite, not reject — so rounding never breaks a booking)
--   A BEFORE INSERT OR UPDATE trigger on public.job_offers recomputes the
--   minimum legitimate fare server-side from the row's own fields using a
--   pricing function that mirrors PricingService, and CLAMPS total_cents UP
--   to that floor. We clamp-up rather than hard-overwrite because the row
--   does not persist the stairs / two-man-crew add-on inputs (only
--   same_hour, size, coordinates and the server-set surge_cents are stored),
--   and those add-ons can only ever raise the total above the floor. Clamping
--   up therefore (a) makes it impossible to pay below the true base + mileage
--   + same-hour + surge price, closing the "set your own price" hole, while
--   (b) never undercharging a legitimate order that legitimately added
--   stairs / crew surcharges on top.
--
--   The same trigger pins payment_status for client (authenticated / anon)
--   writes: on INSERT it is derived server-side purely from whether a
--   payment_intent_id is attached, and on UPDATE clients may not change it at
--   all. The service_role (capture-payment-intent edge fn) and SECURITY
--   DEFINER RPCs (respond_to_offer_upgrade) run as privileged roles and are
--   exempt, so the real capture / re-authorize paths keep working.
--
-- Idempotent: create-or-replace function + drop-then-create trigger.
-- ============================================================

-- ── Pricing floor: mirrors ShypQuick/Services/PricingService.swift ──
--   smallBaseCents = 4500, largeBaseCents = 12500
--   perMileCents   = 350, freeMilesRadius = 10 mi
--   perMileThresholdMeters = 16093.4 (10 mi)
--   sameHourSurchargeCents = 5000
--   total = base + mileageSurcharge + sameHour(+ surge folded server-side)
-- Distance uses the haversine great-circle (Swift uses CLLocation's WGS84
-- geodesic; the two agree to well within rounding for a price floor).
create or replace function public.job_offer_price_floor_cents(
  p_size       text,
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_dropoff_lat double precision,
  p_dropoff_lng double precision,
  p_same_hour  boolean,
  p_surge_cents integer
)
returns integer
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  c_small_base      constant int    := 4500;
  c_large_base      constant int    := 12500;
  c_per_mile_cents  constant int    := 350;
  c_free_radius_mi  constant float8 := 10.0;
  c_per_mile_thresh constant float8 := 16093.4;  -- 10 mi in meters
  c_same_hour       constant int    := 5000;
  c_earth_r_m       constant float8 := 6371000.0;

  v_base      int;
  v_lat1 float8; v_lat2 float8;
  v_dlat float8; v_dlng float8;
  v_a    float8; v_dist_m float8;
  v_miles float8;
  v_mileage int := 0;
  v_rush  int := 0;
  v_surge int;
begin
  -- Base fee by size (matches PricingService.baseCents(for:)).
  v_base := case when p_size = 'large' then c_large_base else c_small_base end;

  -- Haversine distance in meters; NaN/negative-safe like the Swift guard.
  if p_pickup_lat is null or p_pickup_lng is null
     or p_dropoff_lat is null or p_dropoff_lng is null then
    v_dist_m := 0;
  else
    v_lat1 := radians(p_pickup_lat);
    v_lat2 := radians(p_dropoff_lat);
    v_dlat := radians(p_dropoff_lat - p_pickup_lat);
    v_dlng := radians(p_dropoff_lng - p_pickup_lng);
    v_a := sin(v_dlat / 2) ^ 2
         + cos(v_lat1) * cos(v_lat2) * sin(v_dlng / 2) ^ 2;
    v_dist_m := c_earth_r_m * 2 * asin(least(1.0, sqrt(v_a)));
  end if;
  if v_dist_m is null or v_dist_m < 0 or v_dist_m <> v_dist_m then  -- NaN guard
    v_dist_m := 0;
  end if;

  v_miles := v_dist_m / 1609.344;

  -- Mileage surcharge only past the included radius; round, don't truncate.
  if v_dist_m > c_per_mile_thresh then
    v_mileage := round((v_miles - c_free_radius_mi) * c_per_mile_cents)::int;
    if v_mileage < 0 then
      v_mileage := 0;
    end if;
  end if;

  if coalesce(p_same_hour, false) then
    v_rush := c_same_hour;
  end if;

  -- surge_cents is set only by the server-side sweeper; fold it into the floor
  -- so a surged offer can never be re-written below its surged price.
  v_surge := greatest(0, coalesce(p_surge_cents, 0));

  return v_base + v_mileage + v_rush + v_surge;
end;
$$;

-- ── BEFORE INSERT/UPDATE trigger: clamp price + pin payment_status ──
-- NOTE: SECURITY INVOKER (the default) is deliberate. The trigger must see
-- the CALLER's role in current_user to decide whether to pin payment_status.
-- A direct client write runs as 'authenticated'/'anon'; the capture edge fn
-- runs as 'service_role'; and SECURITY DEFINER RPCs (respond_to_offer_upgrade)
-- run as the table owner ('postgres'). Only the first is constrained.
create or replace function public.enforce_offer_pricing()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_floor int;
  -- Only constrain real client roles. service_role (capture edge fn) and
  -- SECURITY DEFINER RPCs (run as the table owner) must stay unconstrained
  -- so captures / re-authorizations land.
  v_is_client boolean := current_user in ('authenticated', 'anon');
begin
  -- 1) Server-authoritative price floor for both customers and drivers.
  v_floor := public.job_offer_price_floor_cents(
    new.size,
    new.pickup_lat, new.pickup_lng,
    new.dropoff_lat, new.dropoff_lng,
    new.same_hour,
    new.surge_cents
  );
  if new.total_cents is null or new.total_cents < v_floor then
    new.total_cents := v_floor;
  end if;

  -- 2) Pin payment_status against client forgery.
  if v_is_client then
    if tg_op = 'INSERT' then
      -- Derive purely from whether a Stripe PI is attached; a client can
      -- never self-assign 'captured' / 'voided' / 'failed' on insert.
      if new.payment_intent_id is not null then
        new.payment_status := 'authorized';
      else
        new.payment_status := 'unauthorized';
      end if;
      -- A client may not claim an authorized hold larger than what it says
      -- it authorized; with no PI there is no hold at all.
      if new.payment_intent_id is null then
        new.authorized_amount_cents := null;
      end if;
    else  -- UPDATE
      -- Clients may not transition payment_status at all; that is reserved
      -- for the capture edge fn (service_role) and the upgrade RPC.
      if new.payment_status is distinct from old.payment_status then
        new.payment_status := old.payment_status;
      end if;
      -- Likewise the captured amount is written only by the capture path.
      if new.captured_amount_cents is distinct from old.captured_amount_cents then
        new.captured_amount_cents := old.captured_amount_cents;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists job_offers_enforce_pricing on public.job_offers;
create trigger job_offers_enforce_pricing
  before insert or update on public.job_offers
  for each row
  execute function public.enforce_offer_pricing();

-- The trigger runs SECURITY INVOKER, so the firing role evaluates the helper:
-- grant EXECUTE on the floor helper to the roles that write job_offers.
-- (The trigger function itself is never called directly — PostgreSQL does not
-- require EXECUTE on a trigger function for the row write that fires it — so it
-- stays revoked from PUBLIC.)
grant execute on function public.job_offer_price_floor_cents(
  text, double precision, double precision, double precision, double precision,
  boolean, integer
) to authenticated, anon, service_role;
revoke all on function public.enforce_offer_pricing() from public;
