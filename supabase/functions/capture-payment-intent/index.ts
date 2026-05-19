// Supabase Edge Function: capture-payment-intent
//
// Called by the capture_on_delivered DB trigger when a job_offers row flips
// to status='delivered' AND has a payment_intent_id. Captures the Stripe
// PaymentIntent and writes payment_status='captured' + captured_amount_cents
// back onto the row.
//
// Auth: deployed with --no-verify-jwt so pg_net can call it. The shared
// secret in `x-payment-webhook-secret` (mirroring push-new-offer) is the only
// thing gating it from public abuse — fail closed if the env var is missing.
//
// Request body (from net.http_post):
//   { "offer_id": "<uuid>", "payment_intent_id": "pi_..." }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
const WEBHOOK_SECRET = Deno.env.get("PAYMENT_WEBHOOK_SECRET");
if (!WEBHOOK_SECRET) {
  throw new Error("PAYMENT_WEBHOOK_SECRET env var is required");
}

interface CapturePayload {
  offer_id: string;
  payment_intent_id: string;
  // Exact amount owed (total_cents). Omitted => capture the full auth.
  amount_cents?: number;
}

serve(async (req) => {
  try {
    const got = req.headers.get("x-payment-webhook-secret") ?? "";
    if (got !== WEBHOOK_SECRET) {
      return json({ error: "forbidden" }, 403);
    }

    if (!STRIPE_SECRET_KEY) {
      // Scaffold mode — the trigger fired but no key is configured yet.
      // Acknowledge so pg_net doesn't keep retrying.
      return json({ error: "stripe_not_configured" }, 503);
    }

    const payload = (await req.json()) as CapturePayload;
    if (!payload?.offer_id || !payload?.payment_intent_id) {
      return json({ error: "missing_fields" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Stripe REST: POST /v1/payment_intents/:id/capture
    // With amount_to_capture we charge exactly what's owed (total_cents);
    // the hold carries surge headroom, so capturing the full auth would
    // over-charge. Without it (no amount_cents) Stripe captures the full auth.
    const captureBody = new URLSearchParams();
    if (typeof payload.amount_cents === "number" && payload.amount_cents > 0) {
      captureBody.set("amount_to_capture", String(Math.floor(payload.amount_cents)));
    }
    const stripeResp = await fetch(
      `https://api.stripe.com/v1/payment_intents/${payload.payment_intent_id}/capture`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: captureBody,
      }
    );
    const text = await stripeResp.text();
    if (!stripeResp.ok) {
      console.error("stripe capture failed", stripeResp.status, text);
      // Mark the row so the team can chase the customer / driver pay-out.
      await supabase
        .from("job_offers")
        .update({ payment_status: "failed" })
        .eq("id", payload.offer_id);
      return json({ error: "stripe_error", status: stripeResp.status, body: text }, 502);
    }
    const pi = JSON.parse(text) as {
      amount_received?: number;
      amount?: number;
      status: string;
    };
    const captured = pi.amount_received ?? pi.amount ?? 0;

    const { error: updateErr } = await supabase
      .from("job_offers")
      .update({
        payment_status: "captured",
        captured_amount_cents: captured,
      })
      .eq("id", payload.offer_id);
    if (updateErr) {
      console.error("post-capture update failed", updateErr);
    }

    return json({ ok: true, captured_amount_cents: captured }, 200);
  } catch (err) {
    console.error("capture-payment-intent error", err);
    return json({ error: String(err) }, 500);
  }
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
