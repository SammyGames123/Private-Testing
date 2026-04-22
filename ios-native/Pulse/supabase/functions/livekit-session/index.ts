import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AccessToken } from "npm:livekit-server-sdk@2.14.0";

type LiveKitRole = "publisher" | "subscriber";

type LiveStreamRow = {
  id: string;
  creator_id: string;
  status: string;
  ended_at: string | null;
  provider_stream_id: string | null;
};

type ProfileRow = {
  display_name: string | null;
  username: string | null;
  email: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const liveKitWsUrl = Deno.env.get("LIVEKIT_WS_URL");
  const liveKitApiKey = Deno.env.get("LIVEKIT_API_KEY");
  const liveKitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");

  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "Supabase function environment is missing SUPABASE_URL or SUPABASE_ANON_KEY." }, 500);
  }

  if (!liveKitWsUrl || !liveKitApiKey || !liveKitApiSecret) {
    return jsonResponse(
      {
        error: "LiveKit is not configured yet. Set LIVEKIT_WS_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET for the livekit-session function.",
      },
      500,
    );
  }

  let body: { stream_id?: string; role?: LiveKitRole } = {};
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  const streamId = body.stream_id?.trim();
  const role = body.role;
  if (!streamId) {
    return jsonResponse({ error: "stream_id is required." }, 400);
  }
  if (role !== "publisher" && role !== "subscriber") {
    return jsonResponse({ error: "role must be publisher or subscriber." }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return jsonResponse({ error: "You need to be signed in to join a live room." }, 401);
  }

  const { data: streamData, error: streamError } = await supabase
    .from("live_streams")
    .select("id, creator_id, status, ended_at, provider_stream_id")
    .eq("id", streamId)
    .limit(1)
    .maybeSingle();

  if (streamError) {
    return jsonResponse({ error: streamError.message }, 400);
  }

  const stream = streamData as LiveStreamRow | null;

  if (!stream) {
    return jsonResponse({ error: "Live stream not found." }, 404);
  }

  if (stream.status !== "live" || stream.ended_at !== null) {
    return jsonResponse({ error: "This live session is no longer active." }, 409);
  }

  const normalizedUserId = user.id.toLowerCase();
  const isCreator = stream.creator_id.toLowerCase() === normalizedUserId;

  if (role === "publisher" && !isCreator) {
    return jsonResponse({ error: "Only the creator can publish to this live room." }, 403);
  }

  const roomName = stream.provider_stream_id?.trim() || `spilltop-live-${stream.id.toLowerCase()}`;
  const participantIdentity = role === "publisher"
    ? `host-${normalizedUserId}`
    : `viewer-${normalizedUserId}`;

  const { data: profileData } = await supabase
    .from("profiles")
    .select("display_name, username, email")
    .eq("id", normalizedUserId)
    .limit(1)
    .maybeSingle();

  const participantName = resolveParticipantName(profileData as ProfileRow | null, user.email, role);

  const token = new AccessToken(liveKitApiKey, liveKitApiSecret, {
    identity: participantIdentity,
    name: participantName,
    ttl: "15m",
  });

  token.addGrant({
    roomJoin: true,
    room: roomName,
    roomAdmin: role === "publisher",
    canPublish: role === "publisher",
    canPublishData: true,
    canSubscribe: true,
  });

  return jsonResponse({
    ws_url: liveKitWsUrl,
    token: await token.toJwt(),
    room_name: roomName,
    participant_identity: participantIdentity,
    participant_name: participantName,
    role,
  });
});

function resolveParticipantName(profile: ProfileRow | null, authEmail: string | undefined, role: LiveKitRole) {
  const candidates = [
    profile?.display_name,
    profile?.username,
    profile?.email,
    authEmail,
  ];

  for (const candidate of candidates) {
    const resolved = normalizeName(candidate);
    if (resolved) {
      return resolved;
    }
  }

  return role === "publisher" ? "Host" : "Guest";
}

function normalizeName(value: string | null | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }

  if (trimmed.includes("@")) {
    return trimmed.split("@")[0] || null;
  }

  return trimmed;
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
