-- Security audit fix: tighten RLS so that authenticated users can no longer
-- enumerate every other user's PII (home_address, phone, live coordinates,
-- pickup/dropoff addresses, item photos).
--
-- Previous policies were "anyone authenticated can SELECT", which on a public
-- repo with a publishable anon key effectively means "anyone on the internet
-- who signs up". This migration scopes reads to (a) the user themselves and
-- (b) the counterparty on a shared delivery / accepted job offer.
--
-- This migration is idempotent: it drops the old policies by name before
-- recreating tightened versions.

-- ============================================================
-- profiles: self + counterparty visibility only
-- ============================================================
drop policy if exists "profiles are viewable by everyone" on public.profiles;
drop policy if exists "users view own profile" on public.profiles;
drop policy if exists "view profile of delivery counterparty" on public.profiles;
drop policy if exists "view profile of job_offer counterparty" on public.profiles;

create policy "users view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "view profile of delivery counterparty"
  on public.profiles for select
  using (
    exists (
      select 1 from public.deliveries d
      where (d.customer_id = auth.uid() and d.driver_id = profiles.id)
         or (d.driver_id   = auth.uid() and d.customer_id = profiles.id)
    )
  );

create policy "view profile of job_offer counterparty"
  on public.profiles for select
  using (
    exists (
      select 1 from public.job_offers o
      where (o.customer_id = auth.uid() and o.driver_id = profiles.id)
         or (o.driver_id   = auth.uid() and o.customer_id = profiles.id)
    )
  );

-- ============================================================
-- job_offers: customer sees own; drivers see only pending+unassigned
-- (so they can decide to accept) or jobs they have been assigned to
-- ============================================================
drop policy if exists "anyone sees pending offers" on public.job_offers;
drop policy if exists "customer sees own offers" on public.job_offers;
drop policy if exists "drivers see pending unassigned offers" on public.job_offers;
drop policy if exists "assigned driver sees offer" on public.job_offers;

create policy "customer sees own offers"
  on public.job_offers for select
  using (auth.uid() = customer_id);

create policy "drivers see pending unassigned offers"
  on public.job_offers for select
  using (
    status = 'pending'
    and driver_id is null
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('driver', 'both')
    )
  );

create policy "assigned driver sees offer"
  on public.job_offers for select
  using (auth.uid() = driver_id);

-- ============================================================
-- driver_locations: driver sees self; customer sees only the driver
-- they have an in-flight job with (accepted offer or active delivery)
-- ============================================================
drop policy if exists "locations are viewable by authenticated users" on public.driver_locations;
drop policy if exists "drivers view own location" on public.driver_locations;
drop policy if exists "customer views assigned driver location" on public.driver_locations;

create policy "drivers view own location"
  on public.driver_locations for select
  using (auth.uid() = driver_id);

create policy "customer views assigned driver location"
  on public.driver_locations for select
  using (
    exists (
      select 1 from public.job_offers o
      where o.driver_id = driver_locations.driver_id
        and o.customer_id = auth.uid()
        and o.status = 'accepted'
    )
    or exists (
      select 1 from public.deliveries d
      where d.driver_id = driver_locations.driver_id
        and d.customer_id = auth.uid()
        and d.status in ('accepted', 'picked_up')
    )
  );

-- ============================================================
-- item-photos storage bucket: make private; access via signed URLs only
-- ============================================================
insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', false)
on conflict (id) do update set public = false;

drop policy if exists "item-photos: customer can upload to own folder" on storage.objects;
drop policy if exists "item-photos: customer can read own uploads" on storage.objects;
drop policy if exists "item-photos: assigned driver can read" on storage.objects;
drop policy if exists "item-photos: anyone authenticated can read" on storage.objects;

-- Customer uploads must live under <auth.uid()>/<file>.jpg so RLS can scope.
create policy "item-photos: customer can upload to own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "item-photos: customer can read own uploads"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Drivers assigned to a job_offer whose photo_url references this object
-- can read it. We match by storing the file path inside the photo_url.
create policy "item-photos: assigned driver can read"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and exists (
      select 1 from public.job_offers o
      where o.driver_id = auth.uid()
        and o.photo_url is not null
        and o.photo_url like '%' || name || '%'
    )
  );

-- Drivers (any user with role driver/both) can read photos belonging to a
-- pending unassigned offer so they can decide whether to accept.
drop policy if exists "item-photos: drivers can read pending offer photos" on storage.objects;
create policy "item-photos: drivers can read pending offer photos"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('driver', 'both')
    )
    and exists (
      select 1 from public.job_offers o
      where o.status = 'pending'
        and o.driver_id is null
        and o.photo_url is not null
        and o.photo_url like '%' || name || '%'
    )
  );

-- ============================================================
-- notify_new_offer: pass shared secret instead of the publishable Bearer key.
--
-- The push-new-offer edge function is deployed with --no-verify-jwt so pg_net
-- can call it; until now the only thing scoping access was a `?? ""` check
-- that silently allowed unauthenticated requests when the env var was unset.
-- The function now requires PUSH_WEBHOOK_SECRET, and this trigger reads the
-- matching value from supabase_vault.
-- ============================================================
create or replace function public.notify_new_offer()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault, pg_catalog
as $$
declare
  webhook_secret text;
begin
  select decrypted_secret
    into webhook_secret
    from vault.decrypted_secrets
    where name = 'push_webhook_secret'
    limit 1;

  perform net.http_post(
    url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-new-offer',
    body    := jsonb_build_object('record', row_to_json(new)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-new-offer-secret', webhook_secret
    )
  );
  return new;
end;
$$;
