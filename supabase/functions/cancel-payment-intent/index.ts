// Supabase Edge Function: cancel-payment-intent
//
// Voids a held PaymentIntent (auth that was never captured). Called by the
// iOS client when a customer cancels before pickup, or when an offer expires
// with no driver. Auth: requires the caller's Supabase JWT — only the
// customer who created the offer may cancel its hold.
//
// Request:  { "offer_id": "<uuid>" }
// Response: { "ok": true } | { error: "..." }
//
// 503 if STRIPE_SECRET_KEY is not configured.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!STRIPE_SECRET_KEY) {
    return json({ error: "stripe_not_configured" }, 503);
  }

  let body: { offer_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (!body?.offer_id) {
    return json({ error: "missing_offer_id" }, 400);
  }

  // Authenticate caller.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  // Look up the offer with the service role so we can verify ownership and
  // grab the PI even if RLS would otherwise hide a cancelled row.
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: rows, error: selectErr } = await admin
    .from("job_offers")
    .select("id, customer_id, payment_intent_id, payment_status")
    .eq("id", body.offer_id)
    .limit(1);
  if (selectErr || !rows?.length) {
    return json({ error: "offer_not_found" }, 404);
  }
  const offer = rows[0];
  if (offer.customer_id !== userData.user.id) {
    return json({ error: "forbidden" }, 403);
  }
  if (!offer.payment_intent_id) {
    return json({ ok: true, note: "no_payment_to_cancel" }, 200);
  }
  if (offer.payment_status === "captured") {
    return json({ error: "already_captured" }, 409);
  }
  if (offer.payment_status === "voided") {
    return json({ ok: true, note: "already_voided" }, 200);
  }

  // Stripe REST: POST /v1/payment_intents/:id/cancel
  const stripeResp = await fetch(
    `https://api.stripe.com/v1/payment_intents/${offer.payment_intent_id}/cancel`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
    }
  );
  const text = await stripeResp.text();
  if (!stripeResp.ok) {
    console.error("stripe cancel failed", stripeResp.status, text);
    return json({ error: "stripe_error", status: stripeResp.status, body: text }, 502);
  }

  await admin
    .from("job_offers")
    .update({ payment_status: "voided" })
    .eq("id", body.offer_id);

  return json({ ok: true }, 200);
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
