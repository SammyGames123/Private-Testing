import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

// Deletes the caller's account. This runs with the service-role key so it
// can touch auth.users, but we always resolve the caller from their own
// JWT first — a user can only delete themselves.
//
// Order of operations:
//   1. Resolve caller from Authorization JWT (anon client).
//   2. Use service-role client to delete the caller's storage objects.
//   3. Delete the profile row (FK cascades handle the rest).
//   4. Delete the auth user.
//
// We do best-effort cleanup on the storage side — a failure there doesn't
// block account deletion.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type VideoRow = { storage_path: string | null; thumbnail_url: string | null };

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse({
      error: "Supabase function environment is missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY.",
    }, 500);
  }

  // Resolve caller from their JWT.
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "You need to be signed in to delete your account." }, 401);
  }

  const userId = user.id;
  const normalizedUserId = userId.toLowerCase();

  // Service-role client for privileged cleanup.
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Best-effort: delete storage-backed videos + thumbnails.
  try {
    const { data: videos } = await admin
      .from("videos")
      .select("storage_path, thumbnail_url")
      .eq("creator_id", normalizedUserId);

    const paths: string[] = [];
    for (const row of (videos ?? []) as VideoRow[]) {
      if (row.storage_path && row.storage_path.length > 0) {
        paths.push(row.storage_path);
      }
      const thumb = storagePathFromPublicURL(row.thumbnail_url, "videos");
      if (thumb) {
        paths.push(thumb);
      }
    }

    if (paths.length > 0) {
      await admin.storage.from("videos").remove(paths);
    }
  } catch (err) {
    console.error("storage cleanup failed", err);
  }

  // Best-effort: delete avatar.
  try {
    const { data: profile } = await admin
      .from("profiles")
      .select("avatar_url")
      .eq("id", normalizedUserId)
      .maybeSingle();
    const avatarPath = storagePathFromPublicURL(
      (profile as { avatar_url: string | null } | null)?.avatar_url ?? null,
      "avatars",
    );
    if (avatarPath) {
      await admin.storage.from("avatars").remove([avatarPath]);
    }
  } catch (err) {
    console.error("avatar cleanup failed", err);
  }

  // Delete profile row. FK cascades should carry videos/comments/follows/
  // blocks/reports, but if a FK is missing we rely on the auth-user delete
  // below to finish the job.
  try {
    await admin.from("profiles").delete().eq("id", normalizedUserId);
  } catch (err) {
    console.error("profile delete failed", err);
  }

  // Delete the auth user. This is the canonical "account is gone" signal.
  const { error: deleteErr } = await admin.auth.admin.deleteUser(userId);
  if (deleteErr) {
    return jsonResponse({ error: deleteErr.message }, 500);
  }

  return jsonResponse({ ok: true });
});

function storagePathFromPublicURL(urlString: string | null, bucket: string): string | null {
  if (!urlString) return null;
  const marker = `/storage/v1/object/public/${bucket}/`;
  const idx = urlString.indexOf(marker);
  if (idx < 0) return null;
  try {
    return decodeURIComponent(urlString.slice(idx + marker.length));
  } catch {
    return urlString.slice(idx + marker.length);
  }
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
