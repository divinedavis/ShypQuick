-- Job offers: posted by customers, received by drivers in real time
create table if not exists public.job_offers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  pickup_address text not null,
  dropoff_address text not null,
  pickup_lat double precision not null,
  pickup_lng double precision not null,
  dropoff_lat double precision not null,
  dropoff_lng double precision not null,
  size text not null check (size in ('small', 'large')),
  same_hour boolean default false,
  total_cents integer not null,
  category_title text not null,
  category_icon text not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'expired')),
  driver_id uuid references public.profiles(id),
  created_at timestamptz default now()
);

create index if not exists job_offers_status_idx on public.job_offers(status);
create index if not exists job_offers_customer_idx on public.job_offers(customer_id);

alter table public.job_offers enable row level security;

-- Any authenticated user can see pending offers
create policy "anyone sees pending offers"
  on public.job_offers for select
  using (auth.role() = 'authenticated');

-- Customers create offers
create policy "customers create offers"
  on public.job_offers for insert
  with check (auth.uid() = customer_id);

-- Customer or accepting driver can update
create policy "update own offers"
  on public.job_offers for update
  using (auth.uid() = customer_id or auth.uid() = driver_id or driver_id is null);

-- Enable realtime for this table
alter publication supabase_realtime add table public.job_offers;
