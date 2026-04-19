// Supabase Edge Function: push-new-offer
// Triggered by a database webhook on job_offers INSERT.
// Sends APNs push notifications to all drivers with stored tokens.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const BUNDLE_ID = "com.Dev.Shyp-Quick";

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
    const payload = await req.json();
    const record = payload.record;

    if (!record || record.status !== "pending") {
      return new Response("Not a pending offer", { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get push tokens for drivers only
    const { data: tokens, error } = await supabase
      .from("push_tokens")
      .select("device_token, user_id, profiles!inner(role)")
      .in("profiles.role", ["driver", "both"]);

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

    // Send to all drivers, trying production then sandbox
    const results = await Promise.allSettled(
      tokens.map(async ({ device_token }: { device_token: string }) => {
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
              body: JSON.stringify(notification),
            }
          );
          const respBody = await resp.text();
          if (resp.status === 200) {
            return { device_token: device_token.substring(0, 8), status: 200, host };
          }
          // If last host also failed, return the error
          if (host === APNS_HOSTS[APNS_HOSTS.length - 1]) {
            return { device_token: device_token.substring(0, 8), status: resp.status, body: respBody };
          }
        }
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
