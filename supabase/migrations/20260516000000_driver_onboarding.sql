-- ============================================================
-- Driver onboarding & roster
-- Implements the SHYPQUICK Driver Onboarding & Roster Checklist
-- (sections 1-10): a roster table, an isolated tax-info table, and
-- a private storage bucket for compliance documents + vehicle photos.
-- ============================================================

-- Generic updated_at trigger ---------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================
-- driver_profiles: one row per driver, keyed to profiles.id.
-- Name and phone already live on profiles; everything else from
-- the onboarding checklist lives here.
-- ============================================================
create table if not exists public.driver_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,

  -- 1. Basic driver information
  date_of_birth date,
  city text,
  state text,
  zip_code text,

  -- 2. Vehicle information
  vehicle_type text check (vehicle_type in
    ('car','suv','pickup_truck','cargo_van','box_truck','flatbed','trailer')),
  vehicle_length_ft numeric(5,1),
  payload_capacity_lbs integer,
  has_lift_gate boolean not null default false,
  vehicle_make text,
  vehicle_model text,
  vehicle_year integer,

  -- 3. Equipment availability
  has_furniture_dolly boolean not null default false,
  has_appliance_dolly boolean not null default false,
  has_moving_blankets boolean not null default false,
  has_ratchet_straps boolean not null default false,
  has_pallet_jack boolean not null default false,
  has_hand_truck boolean not null default false,
  has_ramp boolean not null default false,

  -- 4. Crew information
  crew_type text check (crew_type in ('solo','two_man')),
  additional_helpers_available boolean not null default false,
  white_glove_capable boolean not null default false,

  -- 5. Location & availability
  primary_service_area text,
  max_travel_radius_mi integer,
  operating_states text[] not null default '{}',
  available_weekdays boolean not null default false,
  available_weekends boolean not null default false,
  available_nights boolean not null default false,
  available_on_demand boolean not null default false,

  -- 6. Legal & compliance (object paths in the driver-documents bucket)
  drivers_license_path text,
  insurance_path text,
  vehicle_registration_path text,
  dot_number text,
  background_check_consent boolean not null default false,
  background_check_consent_at timestamptz,

  -- 7. Delivery experience
  exp_furniture boolean not null default false,
  exp_appliance boolean not null default false,
  exp_moving boolean not null default false,
  exp_freight boolean not null default false,
  exp_construction_material boolean not null default false,
  years_experience integer,

  -- 8. Specialized services
  svc_stair_deliveries boolean not null default false,
  svc_assembly_disassembly boolean not null default false,
  svc_appliance_hookups boolean not null default false,
  svc_heavy_item_handling boolean not null default false,

  -- 9. Payment (the tax id is isolated in driver_tax_info)
  preferred_payment_method text check (preferred_payment_method in
    ('ach','cash_app','zelle','paypal')),

  -- 10. Vehicle photo uploads (object paths in the driver-documents bucket)
  vehicle_photo_front_path text,
  vehicle_photo_side_path text,
  vehicle_photo_cargo_path text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists driver_profiles_touch_updated_at on public.driver_profiles;
create trigger driver_profiles_touch_updated_at
  before update on public.driver_profiles
  for each row execute function public.touch_updated_at();

alter table public.driver_profiles enable row level security;

-- Owner-only: a driver sees and edits only their own roster row.
drop policy if exists "drivers manage their own driver profile" on public.driver_profiles;
create policy "drivers manage their own driver profile"
  on public.driver_profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);

-- Drivers are always authenticated; no anon grant (RLS would deny anyway).
revoke all on public.driver_profiles from anon;
grant select, insert, update, delete on public.driver_profiles to authenticated;
grant all on public.driver_profiles to service_role;

-- ============================================================
-- driver_tax_info: SSN/EIN isolated from the roster table so the
-- tax id is never returned by a driver_profiles query. Owner-only
-- RLS; never granted to anon.
-- ============================================================
create table if not exists public.driver_tax_info (
  id uuid primary key references public.profiles(id) on delete cascade,
  tax_id_type text check (tax_id_type in ('ssn','ein')),
  tax_id text,
  updated_at timestamptz not null default now()
);

drop trigger if exists driver_tax_info_touch_updated_at on public.driver_tax_info;
create trigger driver_tax_info_touch_updated_at
  before update on public.driver_tax_info
  for each row execute function public.touch_updated_at();

alter table public.driver_tax_info enable row level security;

drop policy if exists "drivers manage their own tax info" on public.driver_tax_info;
create policy "drivers manage their own tax info"
  on public.driver_tax_info for all
  using (auth.uid() = id) with check (auth.uid() = id);

revoke all on public.driver_tax_info from anon;
grant select, insert, update, delete on public.driver_tax_info to authenticated;
grant all on public.driver_tax_info to service_role;

-- ============================================================
-- driver-documents: private bucket for licenses, insurance,
-- registration, and vehicle photos. Owner-only folder access,
-- matching the item-photos pattern (lowercased uid prefix).
-- ============================================================
insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do nothing;

drop policy if exists "driver-documents: owner can upload" on storage.objects;
create policy "driver-documents: owner can upload"
  on storage.objects for insert
  with check (
    bucket_id = 'driver-documents'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists "driver-documents: owner can read" on storage.objects;
create policy "driver-documents: owner can read"
  on storage.objects for select
  using (
    bucket_id = 'driver-documents'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists "driver-documents: owner can update" on storage.objects;
create policy "driver-documents: owner can update"
  on storage.objects for update
  using (
    bucket_id = 'driver-documents'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists "driver-documents: owner can delete" on storage.objects;
create policy "driver-documents: owner can delete"
  on storage.objects for delete
  using (
    bucket_id = 'driver-documents'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );
