"use server";

import { recordAdminAudit } from "@/lib/admin-audit";
import { broadcastAnnouncement } from "@/lib/push-broadcast";
import { requireAdminClient } from "@/lib/admin";
import { revalidatePath } from "next/cache";

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

  await recordAdminAudit(admin, user.id, "venue.update", "venue", id, {
    name: payload.name,
    latitude: payload.latitude,
    longitude: payload.longitude,
  });

  revalidatePath("/admin");
}

export async function deleteVenueAction(formData: FormData) {
  const { admin, user } = await requireAdminClient();
  const id = stringValue(formData, "id");

  if (!id) {
    throw new Error("Missing venue id.");
  }

  const { data: existingVenue, error: fetchError } = await admin
    .from("venues")
    .select("id, name, slug")
    .eq("id", id)
    .maybeSingle<{ id: string; name: string; slug: string }>();

  if (fetchError) {
    throw new Error(fetchError.message);
  }

  if (!existingVenue) {
    throw new Error("Venue not found.");
  }

  const { error } = await admin.from("venues").delete().eq("id", id);
  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAudit(admin, user.id, "venue.delete", "venue", id, {
    name: existingVenue.name,
    slug: existingVenue.slug,
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

  await recordAdminAudit(admin, user.id, "venue.create", "venue", data.id, {
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

  await recordAdminAudit(admin, user.id, "venue.move", "venue", id, {
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

  await recordAdminAudit(admin, user.id, "report.status", "content_report", id, {
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

  await recordAdminAudit(admin, user.id, "video.archive_from_report", "video", videoId, {
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

  await recordAdminAudit(admin, user.id, "video.delete_from_report", "video", videoId, {
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

  const result = await broadcastAnnouncement(admin, { title, body });

  await recordAdminAudit(admin, user.id, "push.broadcast", "push_broadcast", null, {
    title,
    body,
    recipients_considered: result.recipientsConsidered,
    delivered_users: result.deliveredUsers,
    skipped_users: result.skippedUsers,
    failed_users: result.failedUsers,
  });

  revalidatePath("/admin");
}
