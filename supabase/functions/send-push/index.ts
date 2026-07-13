// Supabase Edge Function: send-push
// Sends native APNs alerts when a row is inserted into public.notifications.
//
// Deploy:
//   supabase functions deploy send-push --no-verify-jwt
//
// Secrets:
//   supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=rytecode.closet
//   supabase secrets set APNS_AUTH_KEY="$(cat AuthKey_XXXXX.p8)"
//
// Wire: Dashboard → Database → Webhooks → INSERT on public.notifications
//   URL: https://<PROJECT_REF>.supabase.co/functions/v1/send-push
//   HTTP Header: Authorization = Bearer <SERVICE_ROLE_KEY>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-webhook-secret",
};

type NotificationRecord = {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string | null;
  payload: Record<string, unknown> | null;
  is_read: boolean;
  created_at: string;
};

type WebhookPayload = {
  type?: string;
  table?: string;
  schema?: string;
  record?: NotificationRecord;
  notification?: NotificationRecord;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
    if (webhookSecret) {
      const provided =
        req.headers.get("x-push-webhook-secret") ??
        req.headers.get("X-Push-Webhook-Secret") ??
        "";
      if (provided !== webhookSecret) {
        return json({ ok: false, error: "Unauthorized webhook" }, 401);
      }
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    }

    const apnsKeyId = Deno.env.get("APNS_KEY_ID");
    const apnsTeamId = Deno.env.get("APNS_TEAM_ID");
    const apnsBundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "rytecode.closet";
    const apnsAuthKey = Deno.env.get("APNS_AUTH_KEY");

    if (!apnsKeyId || !apnsTeamId || !apnsAuthKey) {
      throw new Error("Missing APNS_KEY_ID, APNS_TEAM_ID, or APNS_AUTH_KEY secrets");
    }

    const body = (await req.json()) as WebhookPayload;
    const record = body.record ?? body.notification;
    if (!record?.user_id || !record?.title) {
      return json({ ok: false, error: "No notification record in payload" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: tokens, error: tokenError } = await supabase
      .from("device_tokens")
      .select("token, environment")
      .eq("user_id", record.user_id)
      .eq("platform", "ios");

    if (tokenError) {
      throw tokenError;
    }

    if (!tokens?.length) {
      return json({ ok: true, sent: 0, reason: "no_device_tokens" });
    }

    const jwt = await createApnsJwt(apnsAuthKey, apnsKeyId, apnsTeamId);

    const alertBody =
      (record.body && String(record.body).trim()) ||
      defaultBodyForType(record.type);

    let sent = 0;
    const failures: Array<{ token: string; status: number; reason: string }> = [];

    for (const row of tokens) {
      const useProduction = row.environment === "production";
      const host = useProduction ? "api.push.apple.com" : "api.sandbox.push.apple.com";
      const deviceToken = String(row.token).replace(/\s/g, "");

      const apnsPayload = {
        aps: {
          alert: {
            title: record.title,
            body: alertBody,
          },
          sound: "default",
          badge: 1,
        },
        type: record.type,
        notification_id: record.id,
        payload: record.payload ?? {},
      };

      const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": apnsBundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(apnsPayload),
      });

      if (res.ok) {
        sent += 1;
      } else {
        const reason = await res.text();
        failures.push({
          token: deviceToken.slice(0, 8),
          status: res.status,
          reason,
        });
        if (
          res.status === 410 ||
          reason.includes("BadDeviceToken") ||
          reason.includes("Unregistered")
        ) {
          await supabase.from("device_tokens").delete().eq("token", row.token);
        }
      }
    }

    return json({ ok: true, sent, failures });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("send-push error:", message);
    return json({ ok: false, error: message }, 500);
  }
});

function defaultBodyForType(type: string): string {
  switch (type) {
    case "friend_request":
      return "Open Redress to respond.";
    case "friend_accepted":
      return "You’re now friends.";
    case "outfit_suggestion":
      return "Open Redress to view the suggestion.";
    default:
      return "Open Redress to view.";
  }
}

async function createApnsJwt(
  p8: string,
  keyId: string,
  teamId: string,
): Promise<string> {
  const normalized = p8.includes("\\n") ? p8.replace(/\\n/g, "\n") : p8;
  const key = await importPKCS8(normalized, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .setExpirationTime("50m")
    .sign(key);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
