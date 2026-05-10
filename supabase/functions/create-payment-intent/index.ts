// Supabase Edge Function: create-payment-intent
//
// Called by the iOS app right before posting a job_offers row. Creates a
// Stripe PaymentIntent with capture_method=manual so the customer's card is
// only authorized; capture happens later when the driver marks the job
// delivered (see capture-payment-intent + the capture_on_delivered trigger).
//
// Auth: requires the caller's Supabase JWT. Deployed WITH --verify-jwt.
//
// Request:  { "amount_cents": 4500, "currency": "usd" (optional, default usd) }
// Response: { "client_secret": "...", "payment_intent_id": "pi_..." }
//
// 503 if STRIPE_SECRET_KEY env var is not configured (scaffold mode).

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
// Optional: used to mark off-session payments correctly for repeat customers.
// Stripe customer ids are stored on profiles.stripe_customer_id (added later).

interface CreatePIRequest {
  amount_cents: number;
  currency?: string;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Scaffold mode: until the secret key is configured, surface a clear
  // 503 so the iOS client can fall back to the no-payment flow.
  if (!STRIPE_SECRET_KEY) {
    return json({ error: "stripe_not_configured" }, 503);
  }

  let body: CreatePIRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const amount = Math.floor(Number(body.amount_cents));
  if (!Number.isFinite(amount) || amount <= 0) {
    return json({ error: "invalid_amount" }, 400);
  }
  // Sanity ceiling so a buggy client can't try to authorize $1M.
  if (amount > 1_000_000) {
    return json({ error: "amount_too_large" }, 400);
  }
  const currency = (body.currency ?? "usd").toLowerCase();

  // Identify the caller — the customer who'll be charged.
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }
  const userId = userData.user.id;

  // Stripe REST: POST /v1/payment_intents
  // capture_method=manual → auth now, capture later via /v1/payment_intents/:id/capture
  const params = new URLSearchParams();
  params.set("amount", String(amount));
  params.set("currency", currency);
  params.set("capture_method", "manual");
  // Apple Pay arrives as a "card" PaymentMethod from the iOS SDK.
  params.append("payment_method_types[]", "card");
  params.set("metadata[supabase_user_id]", userId);
  params.set("description", "ShypQuick delivery authorization");

  const resp = await fetch("https://api.stripe.com/v1/payment_intents", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params,
  });
  const text = await resp.text();
  if (!resp.ok) {
    console.error("stripe create PI failed", resp.status, text);
    return json({ error: "stripe_error", status: resp.status, body: text }, 502);
  }
  const pi = JSON.parse(text) as { id: string; client_secret: string };
  return json({ client_secret: pi.client_secret, payment_intent_id: pi.id }, 200);
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
