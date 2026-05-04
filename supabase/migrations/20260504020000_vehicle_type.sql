-- Explicit vehicle_type on job_offers so the driver card can display
-- "Car" or "Truck" prominently. Existing rows are backfilled from size.

alter table public.job_offers
  add column if not exists vehicle_type text
  check (vehicle_type in ('car', 'truck'));

update public.job_offers
  set vehicle_type = case when size = 'small' then 'car' else 'truck' end
  where vehicle_type is null;

-- Update the test seeder so newly generated test offers carry vehicle_type.
create or replace function public.seed_test_offer_if_drivers_online()
returns void
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_customer_id uuid;
  v_online_count int;
  v_scenario jsonb;
  v_scenarios jsonb := '[
    {
      "pickup_address": "Trader Joe''s, Fort Greene, Brooklyn, NY",
      "pickup_lat": 40.6912, "pickup_lng": -73.9742,
      "dropoff_address": "Pratt Institute, Brooklyn, NY",
      "dropoff_lat": 40.6914, "dropoff_lng": -73.9637,
      "size": "small", "vehicle": "car", "title": "Car", "icon": "car.fill", "cents": 4000
    },
    {
      "pickup_address": "The Preserve at Spears Creek, Elgin SC",
      "pickup_lat": 34.0085, "pickup_lng": -80.7896,
      "dropoff_address": "104 Baron Rd, Elgin SC",
      "dropoff_lat": 33.9979, "dropoff_lng": -80.7728,
      "size": "small", "vehicle": "car", "title": "Car", "icon": "car.fill", "cents": 4000
    },
    {
      "pickup_address": "Brooklyn Museum, NY",
      "pickup_lat": 40.6712, "pickup_lng": -73.9636,
      "dropoff_address": "Atlantic Terminal, Brooklyn",
      "dropoff_lat": 40.6843, "dropoff_lng": -73.9777,
      "size": "large", "vehicle": "truck", "title": "Truck", "icon": "truck.box.fill", "cents": 7000
    },
    {
      "pickup_address": "Sandhills, Columbia, SC",
      "pickup_lat": 34.0844, "pickup_lng": -80.9090,
      "dropoff_address": "Two Notch Rd, Columbia, SC",
      "dropoff_lat": 34.0658, "dropoff_lng": -80.9200,
      "size": "large", "vehicle": "truck", "title": "Truck", "icon": "truck.box.fill", "cents": 7000
    }
  ]'::jsonb;
begin
  select count(*) into v_online_count
    from public.driver_locations
    where is_online = true;
  if v_online_count = 0 then
    return;
  end if;

  select id into v_customer_id
    from auth.users
    where email = 'test-customer@shypquick.internal';
  if v_customer_id is null then
    return;
  end if;

  v_scenario := v_scenarios -> floor(random() * jsonb_array_length(v_scenarios))::int;

  insert into public.job_offers (
    customer_id,
    pickup_address, dropoff_address,
    pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
    size, vehicle_type,
    total_cents, category_title, category_icon, status
  ) values (
    v_customer_id,
    v_scenario->>'pickup_address', v_scenario->>'dropoff_address',
    (v_scenario->>'pickup_lat')::double precision,
    (v_scenario->>'pickup_lng')::double precision,
    (v_scenario->>'dropoff_lat')::double precision,
    (v_scenario->>'dropoff_lng')::double precision,
    v_scenario->>'size',
    v_scenario->>'vehicle',
    (v_scenario->>'cents')::int,
    v_scenario->>'title',
    v_scenario->>'icon',
    'pending'
  );
end $$;
