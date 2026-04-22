import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

// APNs sender. Invoked by Postgres triggers (see
// push_notifications_phase4_triggers.sql) whenever something happens that
// might warrant a push — a new like, comment, follow, DM, etc.
//
// Contract
// --------
// POST /send-push
// Headers:
//   X-Webhook-Secret: <PUSH_WEBHOOK_SECRET>
//   Content-Type: application/json
// Body:
//   {
//     "user_id": "<recipient uuid>",
//     "category": "likes" | "comments" | "follows" | "direct_messages" | "live_streams",
//     "title": "<alert title>",
//     "body":  "<alert body>",
//     "data":  { ...optional custom payload... }
//   }
//
// We look up every APNs token this user has, respect their
// notification_preferences, build a JWT with the APNs auth key, and POST
// one alert per device. Failed tokens (410 Gone) are deleted so we stop
// talking to dead devices.

type Category =
  | "likes"
  | "comments"
  | "follows"
  | "direct_messages"
  | "live_streams";

type RequestBody = {
  user_id: string;
  category: Category;
  title: string;
  body: string;
  data?: Record<string, unknown>;
};

type DeviceTokenRow = { token: string; platform: string };

type PreferencesRow = {
  likes: boolean;
  comments: boolean;
  follows: boolean;
  direct_messages: boolean;
  live_streams: boolean;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-secret",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  // 1. Shared-secret gate.
  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!expectedSecret) {
    return json({ error: "PUSH_WEBHOOK_SECRET is not configured." }, 500);
  }
  if (request.headers.get("x-webhook-secret") !== expectedSecret) {
    return json({ error: "Forbidden." }, 403);
  }

  // 2. Parse + validate body.
  let body: RequestBody;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Request body must be valid JSON." }, 400);
  }

  if (!body.user_id || !body.category || !body.title || !body.body) {
    return json({ error: "user_id, category, title, and body are required." }, 400);
  }

  // 3. Read Supabase config + APNs config from env.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apnsKeyId = Deno.env.get("APNS_KEY_ID");
  const apnsTeamId = Deno.env.get("APNS_TEAM_ID");
  const apnsBundleId = Deno.env.get("APNS_BUNDLE_ID");
  const apnsPrivateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const apnsEnvironment = (Deno.env.get("APNS_ENVIRONMENT") ?? "sandbox").toLowerCase();

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing." }, 500);
  }
  if (!apnsKeyId || !apnsTeamId || !apnsBundleId || !apnsPrivateKey) {
    return json({ error: "APNs env vars missing." }, 500);
  }
  if (apnsEnvironment !== "sandbox" && apnsEnvironment !== "production") {
    return json({ error: "APNS_ENVIRONMENT must be 'sandbox' or 'production'." }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 4. Respect user preferences. Missing row = defaults-on.
  const { data: prefsData } = await admin
    .from("notification_preferences")
    .select("likes, comments, follows, direct_messages, live_streams")
    .eq("user_id", body.user_id)
    .maybeSingle();

  const prefs = (prefsData as PreferencesRow | null) ?? {
    likes: true,
    comments: true,
    follows: true,
    direct_messages: true,
    live_streams: true,
  };

  if (!prefs[body.category]) {
    return json({ skipped: true, reason: "preference_off" });
  }

  // 5. Fetch tokens.
  const { data: tokensData, error: tokensError } = await admin
    .from("device_push_tokens")
    .select("token, platform")
    .eq("user_id", body.user_id);

  if (tokensError) {
    return json({ error: tokensError.message }, 500);
  }

  const tokens = ((tokensData ?? []) as DeviceTokenRow[])
    .filter((row) => row.platform === "ios" && row.token);

  if (tokens.length === 0) {
    return json({ skipped: true, reason: "no_tokens" });
  }

  // 6. Build JWT once, reuse across all sends in this invocation.
  const jwt = await buildAppleJwt(apnsPrivateKey, apnsKeyId, apnsTeamId);
  const host = apnsEnvironment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const apnsPayload = {
    aps: {
      alert: { title: body.title, body: body.body },
      sound: "default",
      "mutable-content": 1,
    },
    ...(body.data ?? {}),
    category: body.category,
  };
  const apnsPayloadString = JSON.stringify(apnsPayload);

  const results = await Promise.allSettled(
    tokens.map((row) => sendOne(host, row.token, jwt, apnsBundleId, apnsPayloadString, admin)),
  );

  const sent = results.filter((r) => r.status === "fulfilled" && r.value === true).length;
  const failed = results.length - sent;

  return json({ sent, failed, tokens: tokens.length });
});

async function sendOne(
  host: string,
  deviceToken: string,
  jwt: string,
  bundleId: string,
  payload: string,
  admin: ReturnType<typeof createClient>,
): Promise<boolean> {
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: payload,
  });

  if (response.ok) return true;

  // Reap dead tokens so we don't keep retrying them forever. Apple returns
  // 410 when a token has been permanently removed (app deleted, etc.) and
  // 400 with a "BadDeviceToken" reason when the token format is wrong for
  // the environment (sandbox token sent to production or vice-versa).
  const responseText = await response.text();
  if (
    response.status === 410 ||
    (response.status === 400 && responseText.includes("BadDeviceToken"))
  ) {
    await admin
      .from("device_push_tokens")
      .delete()
      .eq("token", deviceToken);
  }

  console.error(`[send-push] APNs ${response.status}: ${responseText}`);
  return false;
}

// ---------------------------------------------------------------------------
// Apple JWT (ES256)
// ---------------------------------------------------------------------------
//
// APNs accepts a provider token signed with an ECDSA P-256 key. The key
// comes from the .p8 file Apple issues; its body is PKCS#8 PEM.
//
// Header:  { alg: "ES256", kid: <key id>, typ: "JWT" }
// Payload: { iss: <team id>, iat: <unix seconds> }
//
// Tokens are valid for up to an hour; we rebuild every invocation because
// these function instances are usually short-lived.

async function buildAppleJwt(pemKey: string, keyId: string, teamId: string): Promise<string> {
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: teamId, iat: Math.floor(Date.now() / 1000) };

  const encode = (obj: unknown) =>
    base64url(new TextEncoder().encode(JSON.stringify(obj)));

  const signingInput = `${encode(header)}.${encode(payload)}`;
  const key = await importPrivateKey(pemKey);
  const signatureBuffer = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const signature = base64url(new Uint8Array(signatureBuffer));
  return `${signingInput}.${signature}`;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function base64url(bytes: Uint8Array): string {
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
