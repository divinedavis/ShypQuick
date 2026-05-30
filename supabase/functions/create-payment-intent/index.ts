// Supabase Edge Function: create-payment-intent
//
// Called by the iOS app right before posting a job_offers row. Creates a
// Stripe PaymentIntent with capture_method=manual so the customer's card is
// only authorized; capture happens later when the driver marks the job
// delivered (see capture-payment-intent + the capture_on_delivered trigger).
//
// Auth: requires the caller's Supabase JWT. Deployed WITH --verify-jwt.
//
// Request:  { "amount_cents": 4500, "currency": "usd" (optional),
//             // optional trip context — when supplied the hold is floored to
//             // the exact server-computed fare for the trip:
//             "size": "small"|"large", "pickup_lat", "pickup_lng",
//             "dropoff_lat", "dropoff_lng", "same_hour" }
// Response: { "client_secret": "...", "payment_intent_id": "pi_..." }
//
// 503 if STRIPE_SECRET_KEY env var is not configured (scaffold mode).
//
// Security: the authorization amount is the SERVER's decision, not the
// client's. The client-supplied amount_cents is only a lower bound — we clamp
// it UP to a server-authoritative fare floor (base minimum always; the exact
// per-trip floor from job_offer_price_floor_cents when trip context is given)
// so a tampered/tiny amount can never create an under-funded hold. Capture is
// still least(total_cents, authorized_amount_cents) at delivery time.

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
  // Optional trip context. When all four coordinates are present the hold is
  // floored to the exact server-computed fare for this trip.
  size?: string;
  pickup_lat?: number;
  pickup_lng?: number;
  dropoff_lat?: number;
  dropoff_lng?: number;
  same_hour?: boolean;
}

// PricingService.smallBaseCents — the cheapest any real delivery can be.
const ABSOLUTE_MIN_CENTS = 4500;

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

  // ── Server-authoritative authorization floor ──────────────────────────
  // Never authorize a hold below the true minimum fare. Always enforce the
  // base minimum; when the trip context is supplied, enforce the exact
  // per-trip floor computed by the SAME function the job_offers pricing
  // trigger uses (job_offer_price_floor_cents), so the hold matches the
  // amount that will actually be owed. Clamp UP (never reject) so a
  // legitimate request that adds surge headroom keeps its larger hold.
  let floor = ABSOLUTE_MIN_CENTS;
  const pLat = Number(body.pickup_lat);
  const pLng = Number(body.pickup_lng);
  const dLat = Number(body.dropoff_lat);
  const dLng = Number(body.dropoff_lng);
  if ([pLat, pLng, dLat, dLng].every((v) => Number.isFinite(v))) {
    const { data: floorData, error: floorErr } = await supabase.rpc(
      "job_offer_price_floor_cents",
      {
        p_size: body.size === "large" ? "large" : "small",
        p_pickup_lat: pLat,
        p_pickup_lng: pLng,
        p_dropoff_lat: dLat,
        p_dropoff_lng: dLng,
        p_same_hour: body.same_hour === true,
        p_surge_cents: 0,
      },
    );
    if (floorErr) {
      console.error("price floor rpc failed", floorErr.message);
    } else if (Number.isFinite(Number(floorData))) {
      floor = Math.max(ABSOLUTE_MIN_CENTS, Math.floor(Number(floorData)));
    }
  }
  const authorizedAmount = Math.max(amount, floor);
  if (authorizedAmount > 1_000_000) {
    return json({ error: "amount_too_large" }, 400);
  }

  // Stripe REST: POST /v1/payment_intents
  // capture_method=manual → auth now, capture later via /v1/payment_intents/:id/capture
  const params = new URLSearchParams();
  params.set("amount", String(authorizedAmount));
  params.set("currency", currency);
  params.set("capture_method", "manual");
  // Apple Pay arrives as a "card" PaymentMethod from the iOS SDK.
  params.append("payment_method_types[]", "card");
  params.set("metadata[supabase_user_id]", userId);
  params.set("metadata[requested_cents]", String(amount));
  params.set("metadata[floor_cents]", String(floor));
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
