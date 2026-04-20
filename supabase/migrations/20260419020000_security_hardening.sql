-- Security + integrity hardening pass
-- Tightens RLS, adds missing constraints and indexes, and extends realtime publication.

-- ============================================================
-- job_offers: close the "driver_id is null" update hole
-- ============================================================
drop policy if exists "update own offers" on public.job_offers;

-- A driver can claim a pending, unassigned offer (transition from driver_id null -> self).
create policy "drivers can claim pending offers"
  on public.job_offers for update
  using (status = 'pending' and driver_id is null and auth.role() = 'authenticated')
  with check (auth.uid() = driver_id);

-- Once assigned, only the customer or the assigned driver may further update.
create policy "assigned parties update offers"
  on public.job_offers for update
  using (auth.uid() = customer_id or auth.uid() = driver_id)
  with check (auth.uid() = customer_id or auth.uid() = driver_id);

-- job_offers indexes
create index if not exists job_offers_driver_idx on public.job_offers(driver_id);
create index if not exists job_offers_status_created_idx
  on public.job_offers(status, created_at desc);

-- ============================================================
-- deliveries: non-negative price
-- ============================================================
alter table public.deliveries
  drop constraint if exists deliveries_price_cents_positive;
alter table public.deliveries
  add constraint deliveries_price_cents_positive check (price_cents >= 0);

-- ============================================================
-- job_offers: non-negative total
-- ============================================================
alter table public.job_offers
  drop constraint if exists job_offers_total_cents_positive;
alter table public.job_offers
  add constraint job_offers_total_cents_positive check (total_cents >= 0);

-- ============================================================
-- driver_locations: index on is_online for edge function query
-- ============================================================
create index if not exists driver_locations_online_idx
  on public.driver_locations(is_online) where is_online = true;

-- ============================================================
-- ratings: add update/delete policies so users can edit their own
-- ============================================================
drop policy if exists "users update their own ratings" on public.ratings;
create policy "users update their own ratings"
  on public.ratings for update
  using (auth.uid() = rater_id)
  with check (auth.uid() = rater_id);

drop policy if exists "users delete their own ratings" on public.ratings;
create policy "users delete their own ratings"
  on public.ratings for delete
  using (auth.uid() = rater_id);

-- ============================================================
-- profiles: constrain rating range
-- ============================================================
alter table public.profiles
  drop constraint if exists profiles_rating_range;
alter table public.profiles
  add constraint profiles_rating_range check (rating is null or (rating >= 1.0 and rating <= 5.0));

-- ============================================================
-- handle_new_user: make idempotent
-- ============================================================
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

-- ============================================================
-- Realtime: expose driver_locations so the customer can watch
-- their assigned driver move in real time
-- ============================================================
do $$ begin
  alter publication supabase_realtime add table public.driver_locations;
exception when duplicate_object then null;
end $$;
