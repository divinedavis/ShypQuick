-- Payments scaffold: Stripe-backed Apple Pay flow.
--
-- Auth-on-request, capture-on-delivery:
--   1. iOS calls create-payment-intent edge fn → Stripe PI with capture_method=manual.
--   2. iOS presents Stripe PaymentSheet (Apple Pay enabled). On confirm, the card
--      auth is held but not yet captured.
--   3. iOS posts the job_offers row with payment_intent_id set.
--   4. When the driver marks the job delivered, the trigger below fires
--      net.http_post to capture-payment-intent, which captures the funds and
--      writes back payment_status='captured' + captured_amount_cents.
--
-- Rows without a payment_intent_id (e.g. legacy offers, or builds where the
-- Stripe key isn't configured yet) skip the capture call entirely so the
-- existing free-flow behavior keeps working.

-- ============================================================
-- Columns on job_offers
-- ============================================================
alter table public.job_offers
  add column if not exists payment_intent_id      text,
  add column if not exists authorized_amount_cents integer,
  add column if not exists captured_amount_cents   integer,
  add column if not exists payment_status          text not null default 'unauthorized';

-- Drop a stale check if a previous run left one behind, then re-add.
alter table public.job_offers
  drop constraint if exists job_offers_payment_status_check;
alter table public.job_offers
  add constraint job_offers_payment_status_check
  check (payment_status in ('unauthorized','authorized','captured','voided','failed'));

-- payment_intent_id is unique when present (one Stripe PI ↔ one job).
create unique index if not exists job_offers_payment_intent_id_uidx
  on public.job_offers (payment_intent_id)
  where payment_intent_id is not null;

-- ============================================================
-- Allow 'delivered' as a terminal status.
--
-- DispatchService.completeActiveJob already writes 'delivered'; the original
-- check constraint didn't include it. Drop and re-add with the full set.
-- ============================================================
alter table public.job_offers
  drop constraint if exists job_offers_status_check;
alter table public.job_offers
  add constraint job_offers_status_check
  check (status in ('pending','accepted','declined','expired','delivered','cancelled'));

-- ============================================================
-- capture_on_delivered trigger
--
-- Fires net.http_post to the capture-payment-intent edge fn when a row
-- transitions to status='delivered' AND has a payment_intent_id. The
-- shared secret is read from supabase_vault, mirroring notify_new_offer.
-- ============================================================
create or replace function public.capture_on_delivered()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault, pg_catalog
as $$
declare
  webhook_secret text;
begin
  -- Only fire on the pending→delivered (or accepted→delivered) transition.
  if new.status is distinct from 'delivered' or old.status = 'delivered' then
    return new;
  end if;

  -- Skip rows that weren't paid (notConfigured fallback path).
  if new.payment_intent_id is null then
    return new;
  end if;

  -- Don't double-capture.
  if new.payment_status = 'captured' then
    return new;
  end if;

  select decrypted_secret
    into webhook_secret
    from vault.decrypted_secrets
    where name = 'payment_webhook_secret'
    limit 1;

  -- If the secret isn't configured yet, no-op rather than blocking the
  -- delivery transition. The capture function would reject us anyway.
  if webhook_secret is null then
    return new;
  end if;

  perform net.http_post(
    url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/capture-payment-intent',
    body    := jsonb_build_object(
      'offer_id',          new.id,
      'payment_intent_id', new.payment_intent_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-payment-webhook-secret', webhook_secret
    )
  );

  return new;
end;
$$;

drop trigger if exists job_offers_capture_on_delivered on public.job_offers;
create trigger job_offers_capture_on_delivered
  after update of status on public.job_offers
  for each row
  execute function public.capture_on_delivered();
