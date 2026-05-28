-- Bound sweep_pending_offers so abandoned offers stop spamming pg_net.
--
-- Disk IO incident 2026-05-28: net._http_response had grown to 2.6 GB / 113k
-- rows on ywacxbvqtofjglnmzkfi. Root cause = 1,571 stale "pending" job_offers
-- with no driver, each re-broadcast every 5 min by sweep_pending_offers
-- (≈18.8k pg_net calls/hour). The original sweep had no upper age bound, so
-- abandoned test/dev orders accumulated forever.
--
-- Fix:
--   1. Expire any pending offers older than 1 hour with no driver — they are
--      not getting picked up; customer should re-create. notify_offer_status_change
--      ignores the 'expired' status so this does not fan out via pg_net.
--   2. Rewrite sweep_pending_offers to only loop over offers in the active
--      window (created within the last hour) and where surge has not capped.
--      A separate one-shot pass marks anything that ages out of the window
--      as 'expired' so the table doesn't accumulate dead pending rows.

-- ── #1 expire the existing backlog ─────────────────────────
update public.job_offers
   set status = 'expired'
 where status     = 'pending'
   and driver_id  is null
   and created_at < now() - interval '1 hour';

-- ── #2 rewrite sweep to be self-bounding ───────────────────
create or replace function public.sweep_pending_offers()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_id           uuid;
  v_fresh        public.job_offers%rowtype;
  webhook_secret text;
  c_step constant int := 500;   -- +$5
  c_cap  constant int := 3000;  -- +$30
  c_max_age constant interval := interval '1 hour';
begin
  -- Age out anything past the active window before we sweep. notify_offer_status_change
  -- skips 'expired', so this UPDATE does not call net.http_post.
  update public.job_offers
     set status = 'expired'
   where status     = 'pending'
     and driver_id  is null
     and created_at < now() - c_max_age;

  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  for v_id in
    select id from public.job_offers
    where status = 'pending'
      and driver_id is null
      and created_at < now() - interval '5 minutes'
      and created_at > now() - c_max_age
      and surge_cents < c_cap
  loop
    update public.job_offers
       set total_cents   = total_cents + c_step,
           surge_cents   = surge_cents + c_step,
           last_surge_at = now()
     where id = v_id
       and surge_cents < c_cap
       and coalesce(last_surge_at, created_at) < now() - interval '5 minutes';

    select * into v_fresh from public.job_offers where id = v_id;
    perform net.http_post(
      url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/push-new-offer',
      body    := jsonb_build_object('record', row_to_json(v_fresh)),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-new-offer-secret', webhook_secret
      )
    );
  end loop;
end $$;
