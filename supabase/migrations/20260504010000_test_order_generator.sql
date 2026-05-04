-- Pre-launch test data: every 5 minutes, while at least one driver is
-- online, drop a synthetic job_offer into the queue. With no drivers
-- online the function returns early so the DB doesn't accumulate junk.
--
-- Owned by a system "test customer" auth user (created idempotently
-- below); identifiable by the @shypquick.internal email domain so we
-- can clean it all out before going live.

create extension if not exists pg_cron with schema extensions;

-- ============================================================
-- Idempotent test customer auth user + profile
-- ============================================================
do $$
declare
  v_id uuid;
begin
  select id into v_id
    from auth.users
    where email = 'test-customer@shypquick.internal';

  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      is_super_admin, confirmation_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_id,
      'authenticated', 'authenticated',
      'test-customer@shypquick.internal',
      extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"role":"customer","full_name":"Test Customer"}'::jsonb,
      false, ''
    );
  end if;

  insert into public.profiles (id, full_name, role)
  values (v_id, 'Test Customer', 'customer')
  on conflict (id) do update set role = 'customer';
end $$;

-- ============================================================
-- Seeder function: insert a test offer iff a driver is online
-- ============================================================
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
      "size": "small", "title": "Car", "icon": "car.fill", "cents": 4000
    },
    {
      "pickup_address": "The Preserve at Spears Creek, Elgin SC",
      "pickup_lat": 34.0085, "pickup_lng": -80.7896,
      "dropoff_address": "104 Baron Rd, Elgin SC",
      "dropoff_lat": 33.9979, "dropoff_lng": -80.7728,
      "size": "small", "title": "Car", "icon": "car.fill", "cents": 4000
    },
    {
      "pickup_address": "Brooklyn Museum, NY",
      "pickup_lat": 40.6712, "pickup_lng": -73.9636,
      "dropoff_address": "Atlantic Terminal, Brooklyn",
      "dropoff_lat": 40.6843, "dropoff_lng": -73.9777,
      "size": "large", "title": "Truck", "icon": "truck.box.fill", "cents": 7000
    },
    {
      "pickup_address": "Sandhills, Columbia, SC",
      "pickup_lat": 34.0844, "pickup_lng": -80.9090,
      "dropoff_address": "Two Notch Rd, Columbia, SC",
      "dropoff_lat": 34.0658, "dropoff_lng": -80.9200,
      "size": "large", "title": "Truck", "icon": "truck.box.fill", "cents": 7000
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
    size, total_cents, category_title, category_icon, status
  ) values (
    v_customer_id,
    v_scenario->>'pickup_address', v_scenario->>'dropoff_address',
    (v_scenario->>'pickup_lat')::double precision,
    (v_scenario->>'pickup_lng')::double precision,
    (v_scenario->>'dropoff_lat')::double precision,
    (v_scenario->>'dropoff_lng')::double precision,
    v_scenario->>'size',
    (v_scenario->>'cents')::int,
    v_scenario->>'title',
    v_scenario->>'icon',
    'pending'
  );
end $$;

-- ============================================================
-- Schedule: every 5 minutes
-- ============================================================
do $$
begin
  -- Drop any existing version so reruns of this migration replace it
  perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'seed-test-offer-every-5-min';

  perform cron.schedule(
    'seed-test-offer-every-5-min',
    '*/5 * * * *',
    $cron$ select public.seed_test_offer_if_drivers_online(); $cron$
  );
end $$;
