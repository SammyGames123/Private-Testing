"use server";

import { requireAdminClient } from "@/lib/admin";
import { revalidatePath } from "next/cache";
import type { SupabaseClient } from "@supabase/supabase-js";

function stringValue(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

function nullableStringValue(formData: FormData, key: string) {
  const value = stringValue(formData, key);
  return value.length > 0 ? value : null;
}

function numberValue(formData: FormData, key: string) {
  const raw = stringValue(formData, key);
  if (!raw) {
    return null;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function functionsBaseUrl() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!supabaseUrl) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL.");
  }

  const url = new URL(supabaseUrl);
  const projectRef = url.hostname.split(".")[0];
  return `https://${projectRef}.functions.supabase.co`;
}

function requirePushWebhookSecret() {
  const secret = process.env.PUSH_WEBHOOK_SECRET;
  if (!secret) {
    throw new Error("Admin bulk notifications need PUSH_WEBHOOK_SECRET configured in Vercel.");
  }
  return secret;
}

function chunk<T>(items: T[], size: number) {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function storagePathFromPublicUrl(publicUrl: string | null, bucketId: string) {
  if (!publicUrl) {
    return null;
  }

  try {
    const url = new URL(publicUrl);
    const marker = `/storage/v1/object/public/${bucketId}/`;
    const index = url.pathname.indexOf(marker);
    if (index === -1) {
      return null;
    }
    const path = decodeURIComponent(url.pathname.slice(index + marker.length));
    return path.length > 0 ? path : null;
  } catch {
    return null;
  }
}

async function recordAdminAction(
  admin: SupabaseClient,
  actorId: string,
  action: string,
  targetType: string,
  targetId: string | null,
  metadata: Record<string, unknown> = {},
) {
  // The audit table is created by supabase/admin_mvp.sql. Do not block the
  // admin workflow if the migration has not been applied yet.
  try {
    await admin.from("admin_audit_log").insert({
      actor_id: actorId,
      action,
      target_type: targetType,
      target_id: targetId,
      metadata,
    });
  } catch {
    // Optional audit table is missing or temporarily unavailable.
  }
}

export async function saveVenueAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const id = stringValue(formData, "id");

  if (!id) {
    throw new Error("Missing venue id.");
  }

  const payload = {
    name: stringValue(formData, "name"),
    slug: stringValue(formData, "slug"),
    area: stringValue(formData, "area") || "Surfers Paradise",
    city: stringValue(formData, "city") || "Gold Coast",
    category: stringValue(formData, "category") || "bar",
    vibe_blurb: nullableStringValue(formData, "vibe_blurb"),
    address: nullableStringValue(formData, "address"),
    latitude: numberValue(formData, "latitude"),
    longitude: numberValue(formData, "longitude"),
    launch_priority: numberValue(formData, "launch_priority") ?? 0,
    price_level: numberValue(formData, "price_level"),
    nightlife_score: numberValue(formData, "nightlife_score"),
    is_active: formData.get("is_active") === "on",
    featured: formData.get("featured") === "on",
    updated_at: new Date().toISOString(),
  };

  const { error } = await admin.from("venues").update(payload).eq("id", id);
  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAction(admin, user.id, "venue.update", "venue", id, {
    name: payload.name,
    latitude: payload.latitude,
    longitude: payload.longitude,
  });

  revalidatePath("/admin");
}

export async function createVenueAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();

  const name = stringValue(formData, "name");
  const slug = stringValue(formData, "slug");

  if (!name || !slug) {
    throw new Error("Venue name and slug are required.");
  }

  const payload = {
    name,
    slug,
    area: stringValue(formData, "area") || "Surfers Paradise",
    city: stringValue(formData, "city") || "Gold Coast",
    category: stringValue(formData, "category") || "bar",
    vibe_blurb: nullableStringValue(formData, "vibe_blurb"),
    address: nullableStringValue(formData, "address"),
    latitude: numberValue(formData, "latitude"),
    longitude: numberValue(formData, "longitude"),
    launch_priority: numberValue(formData, "launch_priority") ?? 250,
    price_level: numberValue(formData, "price_level"),
    nightlife_score: numberValue(formData, "nightlife_score"),
    is_active: true,
    featured: formData.get("featured") === "on",
  };

  const { data, error } = await admin
    .from("venues")
    .insert(payload)
    .select("id")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAction(admin, user.id, "venue.create", "venue", data.id, {
    name,
    slug,
  });

  revalidatePath("/admin");
}

export async function updateVenueCoordinatesAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const id = stringValue(formData, "id");
  const name = stringValue(formData, "name");
  const slug = stringValue(formData, "slug");
  const latitude = numberValue(formData, "latitude");
  const longitude = numberValue(formData, "longitude");

  if (!id || !name || !slug || latitude == null || longitude == null) {
    throw new Error("Venue, name, slug, latitude, and longitude are required.");
  }

  const { error } = await admin
    .from("venues")
    .update({
      name,
      slug,
      latitude,
      longitude,
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAction(admin, user.id, "venue.move", "venue", id, {
    name,
    slug,
    latitude,
    longitude,
  });

  revalidatePath("/admin");
}

export async function updateReportStatusAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const id = stringValue(formData, "id");
  const status = stringValue(formData, "status");

  if (!id || !["open", "reviewing", "dismissed", "actioned"].includes(status)) {
    throw new Error("Invalid report status.");
  }

  const { error } = await admin
    .from("content_reports")
    .update({
      status,
      resolved_at: status === "dismissed" || status === "actioned" ? new Date().toISOString() : null,
    })
    .eq("id", id);

  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAction(admin, user.id, "report.status", "content_report", id, {
    status,
  });

  revalidatePath("/admin");
}

export async function archiveReportedVideoAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const reportId = stringValue(formData, "report_id");
  const videoId = stringValue(formData, "video_id");

  if (!reportId || !videoId) {
    throw new Error("Report id and video id are required.");
  }

  const now = new Date().toISOString();
  const { error: videoError } = await admin
    .from("videos")
    .update({
      is_archived: true,
      updated_at: now,
    })
    .eq("id", videoId);

  if (videoError) {
    throw new Error(videoError.message);
  }

  const { error: reportError } = await admin
    .from("content_reports")
    .update({
      status: "actioned",
      resolved_at: now,
    })
    .eq("id", reportId);

  if (reportError) {
    throw new Error(reportError.message);
  }

  await recordAdminAction(admin, user.id, "video.archive_from_report", "video", videoId, {
    report_id: reportId,
  });

  revalidatePath("/admin");
}

export async function deleteReportedVideoAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const reportId = stringValue(formData, "report_id");
  const videoId = stringValue(formData, "video_id");

  if (!reportId || !videoId) {
    throw new Error("Report id and video id are required.");
  }

  const { data: videoRow, error: fetchError } = await admin
    .from("videos")
    .select("storage_path, playback_url, thumbnail_url")
    .eq("id", videoId)
    .maybeSingle<{
      storage_path: string | null;
      playback_url: string | null;
      thumbnail_url: string | null;
    }>();

  if (fetchError) {
    throw new Error(fetchError.message);
  }

  const storagePaths = new Set<string>();
  if (videoRow?.storage_path) {
    storagePaths.add(videoRow.storage_path);
  }

  const playbackStoragePath = storagePathFromPublicUrl(videoRow?.playback_url ?? null, "videos");
  if (playbackStoragePath) {
    storagePaths.add(playbackStoragePath);
  }

  const thumbnailStoragePath = storagePathFromPublicUrl(videoRow?.thumbnail_url ?? null, "videos");
  if (thumbnailStoragePath) {
    storagePaths.add(thumbnailStoragePath);
  }

  const { error: deleteError } = await admin
    .from("videos")
    .delete()
    .eq("id", videoId);

  if (deleteError) {
    throw new Error(deleteError.message);
  }

  if (storagePaths.size > 0) {
    try {
      await admin.storage.from("videos").remove(Array.from(storagePaths));
    } catch {
      // The post row is already gone. Do not block the moderation action if
      // storage cleanup lags behind.
    }
  }

  await recordAdminAction(admin, user.id, "video.delete_from_report", "video", videoId, {
    report_id: reportId,
    removed_paths: Array.from(storagePaths),
  });

  revalidatePath("/admin");
}

export async function sendBroadcastNotificationAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const title = stringValue(formData, "title");
  const body = stringValue(formData, "body");

  if (!title || !body) {
    throw new Error("Broadcast title and message are required.");
  }

  const { data: tokenRows, error: tokenError } = await admin
    .from("device_push_tokens")
    .select("user_id");

  if (tokenError) {
    throw new Error(tokenError.message);
  }

  const userIds = Array.from(
    new Set(
      ((tokenRows ?? []) as Array<{ user_id: string | null }>)
        .map((row) => row.user_id?.toLowerCase())
        .filter((value): value is string => Boolean(value)),
    ),
  );

  if (!userIds.length) {
    throw new Error("No registered push recipients were found.");
  }

  const webhookSecret = requirePushWebhookSecret();
  const endpoint = `${functionsBaseUrl()}/send-push`;
  let deliveredUsers = 0;
  let skippedUsers = 0;
  let failedUsers = 0;

  for (const batch of chunk(userIds, 25)) {
    const results = await Promise.allSettled(
      batch.map(async (userId) => {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Webhook-Secret": webhookSecret,
          },
          body: JSON.stringify({
            user_id: userId,
            category: "announcements",
            title,
            body,
            data: {
              category: "announcements",
            },
          }),
        });

        let payload: Record<string, unknown> | null = null;
        try {
          payload = (await response.json()) as Record<string, unknown>;
        } catch {
          payload = null;
        }

        if (!response.ok) {
          throw new Error(
            typeof payload?.error === "string" && payload.error.length > 0
              ? payload.error
              : `Push request failed with status ${response.status}.`,
          );
        }

        return payload;
      }),
    );

    for (const result of results) {
      if (result.status !== "fulfilled") {
        failedUsers += 1;
        continue;
      }

      const payload = result.value;
      if (payload && payload.skipped === true) {
        skippedUsers += 1;
        continue;
      }

      if (payload && typeof payload.sent === "number" && payload.sent > 0) {
        deliveredUsers += 1;
      } else {
        skippedUsers += 1;
      }
    }
  }

  await recordAdminAction(admin, user.id, "push.broadcast", "push_broadcast", null, {
    title,
    body,
    recipients_considered: userIds.length,
    delivered_users: deliveredUsers,
    skipped_users: skippedUsers,
    failed_users: failedUsers,
  });

  revalidatePath("/admin");
}
