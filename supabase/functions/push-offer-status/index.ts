// Supabase Edge Function: push-offer-status
// Triggered by the on_job_offer_status_change DB trigger when a
// job_offers row changes status. Sends the CUSTOMER an APNs push so
// they know a driver accepted / picked up / delivered their order.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
// Same shared secret the DB trigger sends for push-new-offer — the
// function is deployed --no-verify-jwt so pg_net can call it, and this
// header is the only thing gating it. Fail closed if it's missing.
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET");
if (!WEBHOOK_SECRET) {
  throw new Error("PUSH_WEBHOOK_SECRET env var is required");
}
const BUNDLE_ID = "com.Dev.Shyp-Quick";
const APNS_PAYLOAD_MAX_BYTES = 4096;
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

// Customer-facing copy for each status the trigger forwards.
function messageFor(status: string, category: string, dropoff: string):
  { title: string; body: string } | null {
  switch (status) {
    case "accepted":
      return {
        title: "Driver on the way! 🚚",
        body: `A driver accepted your ${category} delivery and is heading to pickup.`,
      };
    case "picked_up":
      return {
        title: "Package picked up 📦",
        body: `Your ${category} is on the way to ${dropoff}.`,
      };
    case "delivered":
      return {
        title: "Delivered 🎉",
        body: `Your ${category} delivery is complete.`,
      };
    default:
      return null;
  }
}

serve(async (req) => {
  try {
    const got = req.headers.get("x-push-new-offer-secret") ?? "";
    if (got !== WEBHOOK_SECRET) {
      return new Response("Forbidden", { status: 403 });
    }

    const payload = await req.json();
    const record = payload.record;
    if (!record || !record.customer_id) {
      return new Response("Not a notifiable change", { status: 200 });
    }

    // A driver-proposed Car→Truck upgrade is awaiting the customer's OK.
    let message: { title: string; body: string } | null;
    if (typeof record.proposed_total_cents === "number") {
      const newDollars = (record.proposed_total_cents / 100).toFixed(2);
      message = {
        title: "Your driver needs a Truck 🚚",
        body: `Approve the upgrade in the app — your total would become $${newDollars}.`,
      };
    } else {
      message = messageFor(
        record.status ?? "",
        record.category_title ?? "delivery",
        record.dropoff_address ?? "the drop-off",
      );
    }
    if (!message) {
      return new Response("Nothing customer-facing to send", { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Push tokens for the customer who owns this offer.
    const { data: tokens, error } = await supabase
      .from("push_tokens")
      .select("device_token")
      .eq("user_id", record.customer_id);

    if (error || !tokens?.length) {
      return new Response("No tokens", { status: 200 });
    }

    const apnsToken = await getApnsToken();
    const notification = {
      aps: {
        alert: { title: message.title, body: message.body },
        sound: "default",
        badge: 1,
      },
      offer_id: record.id,
      offer_status: record.status,
    };
    const body = JSON.stringify(notification);
    if (new TextEncoder().encode(body).length > APNS_PAYLOAD_MAX_BYTES) {
      return new Response(
        JSON.stringify({ error: "payload_too_large", bytes: body.length }),
        { status: 413, headers: { "Content-Type": "application/json" } },
      );
    }

    async function purgeToken(deviceToken: string, reason: string) {
      try {
        await supabase.from("push_tokens").delete().eq("device_token", deviceToken);
      } catch (_) { /* ignore */ }
      console.log(`purged token ${deviceToken.substring(0, 8)}… (${reason})`);
    }

    const results = await Promise.allSettled(
      tokens.map(async ({ device_token }: { device_token: string }) => {
        let lastStatus = 0;
        let lastBody = "";
        for (const host of APNS_HOSTS) {
          const resp = await fetch(`${host}/3/device/${device_token}`, {
            method: "POST",
            headers: {
              authorization: `bearer ${apnsToken}`,
              "apns-topic": BUNDLE_ID,
              "apns-push-type": "alert",
              "apns-priority": "10",
              "content-type": "application/json",
            },
            body,
          });
          lastStatus = resp.status;
          lastBody = await resp.text();
          if (resp.status === 200) {
            return { device_token: device_token.substring(0, 8), status: 200, host };
          }
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
      }),
    );

    const details = results.map((r: any) =>
      r.status === "fulfilled" ? r.value : { error: String(r.reason) }
    );
    return new Response(JSON.stringify({ sent: results.length, status: record.status, details }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
