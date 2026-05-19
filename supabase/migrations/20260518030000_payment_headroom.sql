-- ============================================================
-- Payment headroom for surge + upgrades
--
-- Surge (+$30) and the driver upgrade (+~$110) raise total_cents
-- after a card was authorized at the original quote — so the
-- capture could come up short.
--
-- Two fixes:
--   1. Capture the ACTUAL total_cents, not the full authorized
--      hold. (The hold now carries surge headroom, so capturing
--      the full hold would OVER-charge a non-surged order.)
--   2. respond_to_offer_upgrade can swap in a fresh PaymentIntent
--      when the customer re-authorizes for the upgraded price.
-- ============================================================

-- ── 1. Capture the actual total, not the whole hold ─────────
create or replace function public.capture_on_delivered()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault, pg_catalog
as $$
declare
  webhook_secret text;
begin
  if new.status is distinct from 'delivered' or old.status = 'delivered' then
    return new;
  end if;
  if new.payment_intent_id is null then
    return new;
  end if;
  if new.payment_status = 'captured' then
    return new;
  end if;

  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets
    where name = 'payment_webhook_secret' limit 1;
  if webhook_secret is null then
    return new;
  end if;

  perform net.http_post(
    url     := 'https://ywacxbvqtofjglnmzkfi.supabase.co/functions/v1/capture-payment-intent',
    body    := jsonb_build_object(
      'offer_id',          new.id,
      'payment_intent_id', new.payment_intent_id,
      -- Capture exactly what's owed, clamped to the authorized hold so
      -- Stripe never rejects the capture for exceeding the auth.
      'amount_cents',      least(
                             new.total_cents,
                             coalesce(new.authorized_amount_cents, new.total_cents)
                           )
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-payment-webhook-secret', webhook_secret
    )
  );
  return new;
end;
$$;

-- ── 2. respond_to_offer_upgrade swaps in the new hold ───────
drop function if exists public.respond_to_offer_upgrade(uuid, boolean);

create or replace function public.respond_to_offer_upgrade(
  p_offer_id          uuid,
  p_approve           boolean,
  p_payment_intent_id text    default null,
  p_authorized_cents  integer default null
)
returns json
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_offer public.job_offers%rowtype;
begin
  select * into v_offer from public.job_offers where id = p_offer_id;
  if not found then
    raise exception 'offer % not found', p_offer_id using errcode = '42704';
  end if;
  if v_offer.customer_id <> auth.uid() then
    raise exception 'only the customer can respond to this upgrade'
      using errcode = '42501';
  end if;
  if v_offer.proposed_total_cents is null then
    raise exception 'no upgrade is awaiting approval' using errcode = '22023';
  end if;

  if p_approve then
    update public.job_offers
       set total_cents          = v_offer.proposed_total_cents,
           vehicle_type         = 'truck',
           size                 = 'large',
           category_title       = 'Truck',
           category_icon        = 'truck.box.fill',
           proposed_total_cents = null,
           proposed_at          = null,
           -- Swap in the re-authorized hold the customer just confirmed.
           -- When no PI is supplied (Stripe not configured / free flow)
           -- the existing payment fields are left untouched.
           payment_intent_id       = coalesce(p_payment_intent_id, payment_intent_id),
           authorized_amount_cents = coalesce(p_authorized_cents, authorized_amount_cents),
           payment_status          = case
                                       when p_payment_intent_id is not null then 'authorized'
                                       else payment_status
                                     end
     where id = p_offer_id;
  else
    update public.job_offers
       set proposed_total_cents = null,
           proposed_at          = null
     where id = p_offer_id;
  end if;

  return json_build_object('approved', p_approve);
end $$;

grant execute on function
  public.respond_to_offer_upgrade(uuid, boolean, text, integer)
  to authenticated;
