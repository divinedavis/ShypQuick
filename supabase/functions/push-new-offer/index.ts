// Supabase Edge Function: push-new-offer
// Triggered by a database webhook on job_offers INSERT.
// Sends APNs push notifications to all online drivers with stored tokens.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
// Shared secret the DB trigger sends in `x-push-new-offer-secret`. If set, we
// reject requests that don't match — closes the abuse hole from --no-verify-jwt.
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const BUNDLE_ID = "com.Dev.Shyp-Quick";
const APNS_PAYLOAD_MAX_BYTES = 4096;

// APNs endpoint (use api.push.apple.com for production)
// Try production first (TestFlight/App Store), fall back to sandbox (Xcode)
const APNS_HOSTS = [
  "https://api.push.apple.com",
  "https://api.sandbox.push.apple.com",
];

async function getApnsToken(): Promise<string> {
  const key = await importPKCS8(APNS_PRIVATE_KEY, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: APNS_KEY_ID })
    .setIssuer(APNS_TEAM_ID)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
}

serve(async (req) => {
  try {
    // Reject requests missing the shared secret (belt-and-suspenders since
    // function is deployed with --no-verify-jwt so it can be called from pg_net).
    if (WEBHOOK_SECRET) {
      const got = req.headers.get("x-push-new-offer-secret") ?? "";
      if (got !== WEBHOOK_SECRET) {
        return new Response("Forbidden", { status: 403 });
      }
    }

    const payload = await req.json();
    const record = payload.record;

    if (!record || record.status !== "pending") {
      return new Response("Not a pending offer", { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get push tokens for online drivers only
    const { data: onlineDrivers } = await supabase
      .from("driver_locations")
      .select("driver_id")
      .eq("is_online", true);

    const onlineIds = (onlineDrivers || []).map((d: any) => d.driver_id);
    if (!onlineIds.length) {
      return new Response("No online drivers", { status: 200 });
    }

    const { data: tokens, error } = await supabase
      .from("push_tokens")
      .select("device_token, user_id")
      .in("user_id", onlineIds);

    if (error || !tokens?.length) {
      return new Response("No tokens", { status: 200 });
    }

    const apnsToken = await getApnsToken();
    const earnings = Math.round(record.total_cents * 0.7);
    const earningsDollars = (earnings / 100).toFixed(2);

    const notification = {
      aps: {
        alert: {
          title: "SHYP Quick — New delivery!",
          body: `${record.category_title} — Earn $${earningsDollars}`,
        },
        sound: "default",
        badge: 1,
      },
      offer_id: record.id,
    };

    const body = JSON.stringify(notification);
    if (new TextEncoder().encode(body).length > APNS_PAYLOAD_MAX_BYTES) {
      return new Response(
        JSON.stringify({ error: "payload_too_large", bytes: body.length }),
        { status: 413, headers: { "Content-Type": "application/json" } }
      );
    }

    // Delete a token that APNs has permanently rejected (410 Gone, or 400
    // BadDeviceToken). Swallow errors — worst case we retry deletion later.
    async function purgeToken(deviceToken: string, reason: string) {
      try {
        await supabase
          .from("push_tokens")
          .delete()
          .eq("device_token", deviceToken);
      } catch (_) { /* ignore */ }
      console.log(`purged token ${deviceToken.substring(0, 8)}… (${reason})`);
    }

    // Send to all drivers, trying production then sandbox
    const results = await Promise.allSettled(
      tokens.map(async ({ device_token }: { device_token: string }) => {
        let lastStatus = 0;
        let lastBody = "";
        for (const host of APNS_HOSTS) {
          const resp = await fetch(
            `${host}/3/device/${device_token}`,
            {
              method: "POST",
              headers: {
                authorization: `bearer ${apnsToken}`,
                "apns-topic": BUNDLE_ID,
                "apns-push-type": "alert",
                "apns-priority": "10",
                "content-type": "application/json",
              },
              body,
            }
          );
          lastStatus = resp.status;
          lastBody = await resp.text();
          if (resp.status === 200) {
            return { device_token: device_token.substring(0, 8), status: 200, host };
          }
          // 410 Gone or 400 BadDeviceToken → token is dead, don't retry other host.
          let reason = "";
          try {
            reason = (JSON.parse(lastBody)?.reason ?? "") as string;
          } catch (_) { /* not json */ }
          if (resp.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
            await purgeToken(device_token, `${resp.status} ${reason}`);
            return { device_token: device_token.substring(0, 8), status: resp.status, purged: true };
          }
        }
        return { device_token: device_token.substring(0, 8), status: lastStatus, body: lastBody };
      })
    );

    const details = results.map((r: any) => r.status === "fulfilled" ? r.value : { error: String(r.reason) });
    return new Response(JSON.stringify({ sent: results.length, details }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
    });
  }
});
