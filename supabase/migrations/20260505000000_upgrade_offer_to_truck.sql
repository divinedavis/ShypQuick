-- Driver-initiated vehicle upgrade. If the customer requested a Car but
-- the item actually needs a Truck, the assigned driver can upgrade the
-- active job from the active-job screen. Only the difference between the
-- Truck and Car base price is added — mileage and same-hour surcharges
-- already in total_cents are preserved.
--
-- Returns the old + new totals so the client can show a price-change
-- confirmation. SECURITY DEFINER so the function can update job_offers
-- on behalf of an authenticated driver, but the caller-identity check
-- gates writes to (a) the assigned driver, (b) status='accepted', and
-- (c) currently a Car offer.

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
  -- These mirror the iOS-side PricingService base prices.
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

  if v_offer.status <> 'accepted' then
    raise exception 'offer must be accepted to upgrade (got %)', v_offer.status
      using errcode = '22023';
  end if;

  if v_offer.vehicle_type = 'truck' then
    raise exception 'offer is already a truck job' using errcode = '22023';
  end if;

  v_old_total := v_offer.total_cents;
  v_new_total := v_old_total - c_car_base + c_truck_base;

  update public.job_offers
     set vehicle_type   = 'truck',
         size           = 'large',
         total_cents    = v_new_total,
         category_title = 'Truck',
         category_icon  = 'truck.box.fill'
   where id = p_offer_id;

  return json_build_object(
    'old_total_cents',  v_old_total,
    'new_total_cents',  v_new_total,
    'difference_cents', v_new_total - v_old_total
  );
end $$;

grant execute on function public.upgrade_offer_to_truck(uuid) to authenticated;
