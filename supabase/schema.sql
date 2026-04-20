-- ShypQuick Supabase schema
-- Run this in the Supabase SQL editor (or `supabase db push`)

-- Enable PostGIS for geo queries (optional but recommended)
create extension if not exists postgis;

-- ============================================================
-- profiles: one row per auth.users, extends with app-specific data
-- ============================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'customer' check (role in ('customer', 'driver', 'both')),
  avatar_url text,
  rating numeric(2,1) default 5.0 check (rating is null or (rating >= 1.0 and rating <= 5.0)),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "profiles are viewable by everyone"
  on public.profiles for select using (true);

create policy "users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);

create policy "users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

-- Auto-create profile row when a user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- deliveries: core job table
-- ============================================================
create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  driver_id uuid references public.profiles(id),

  pickup_address text not null,
  pickup_lat double precision not null,
  pickup_lng double precision not null,

  dropoff_address text not null,
  dropoff_lat double precision not null,
  dropoff_lng double precision not null,

  item_description text,
  item_size text check (item_size in ('small', 'medium', 'large')),

  status text not null default 'requested'
    check (status in ('requested', 'accepted', 'picked_up', 'delivered', 'cancelled')),

  price_cents integer not null check (price_cents >= 0),

  requested_at timestamptz default now(),
  accepted_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz
);

create index if not exists deliveries_customer_idx on public.deliveries(customer_id);
create index if not exists deliveries_driver_idx on public.deliveries(driver_id);
create index if not exists deliveries_status_idx on public.deliveries(status);

alter table public.deliveries enable row level security;

create policy "customers see their own deliveries"
  on public.deliveries for select
  using (auth.uid() = customer_id or auth.uid() = driver_id);

create policy "customers create deliveries"
  on public.deliveries for insert
  with check (auth.uid() = customer_id);

create policy "customer or assigned driver can update"
  on public.deliveries for update
  using (auth.uid() = customer_id or auth.uid() = driver_id);

-- Open (unassigned) deliveries are visible to any authenticated driver
create policy "drivers see open jobs"
  on public.deliveries for select
  using (status = 'requested' and driver_id is null);

-- ============================================================
-- driver_locations: live location pings for online drivers
-- ============================================================
create table if not exists public.driver_locations (
  driver_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  heading double precision,
  is_online boolean default true,
  updated_at timestamptz default now()
);

alter table public.driver_locations enable row level security;

create policy "locations are viewable by authenticated users"
  on public.driver_locations for select
  using (auth.role() = 'authenticated');

create policy "drivers update their own location"
  on public.driver_locations for all
  using (auth.uid() = driver_id) with check (auth.uid() = driver_id);

-- ============================================================
-- ratings
-- ============================================================
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  rater_id uuid not null references public.profiles(id),
  ratee_id uuid not null references public.profiles(id),
  stars integer not null check (stars between 1 and 5),
  comment text,
  created_at timestamptz default now(),
  unique(delivery_id, rater_id)
);

alter table public.ratings enable row level security;

create policy "ratings viewable by everyone"
  on public.ratings for select using (true);

create policy "users rate deliveries they participated in"
  on public.ratings for insert
  with check (auth.uid() = rater_id);

create policy "users update their own ratings"
  on public.ratings for update
  using (auth.uid() = rater_id)
  with check (auth.uid() = rater_id);

create policy "users delete their own ratings"
  on public.ratings for delete
  using (auth.uid() = rater_id);
