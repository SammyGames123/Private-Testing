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
  const latitude = numberValue(formData, "latitude");
  const longitude = numberValue(formData, "longitude");

  if (!id || latitude == null || longitude == null) {
    throw new Error("Venue, latitude, and longitude are required.");
  }

  const { error } = await admin
    .from("venues")
    .update({
      latitude,
      longitude,
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) {
    throw new Error(error.message);
  }

  await recordAdminAction(admin, user.id, "venue.move", "venue", id, {
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
