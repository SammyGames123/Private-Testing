"use server";

import { createClient } from "@/lib/supabase/server";
import { getStatusRedirect } from "@/lib/utils";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

export async function createVideo(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const title = String(formData.get("title") ?? "").trim();
  const caption = String(formData.get("caption") ?? "").trim();
  const category = String(formData.get("category") ?? "").trim();
  const playbackUrl =
    String(formData.get("uploaded_playback_url") ?? "").trim() ||
    String(formData.get("playback_url") ?? "").trim();
  const thumbnailUrl = String(formData.get("thumbnail_url") ?? "").trim();
  const storagePath = String(formData.get("storage_path") ?? "").trim();
  const visibility = String(formData.get("visibility") ?? "public").trim();
  const durationSeconds = Number(formData.get("duration_seconds") ?? 0);
  const tags = String(formData.get("tags") ?? "")
    .split(",")
    .map((tag) => tag.trim().toLowerCase())
    .filter(Boolean)
    .slice(0, 12);

  if (!title) {
    redirect(
      getStatusRedirect("error", "/videos/new", "Please add a title first."),
    );
  }

  if (!playbackUrl) {
    redirect(
      getStatusRedirect(
        "error",
        "/videos/new",
        "Upload a video or photo file, or paste a media URL.",
      ),
    );
  }

  const { data: video, error: insertError } = await supabase
    .from("videos")
    .insert({
      creator_id: user.id,
      title,
      caption: caption || null,
      category: category || null,
      playback_url: playbackUrl,
      thumbnail_url: thumbnailUrl || null,
      storage_path: storagePath || null,
      visibility:
        visibility === "private" || visibility === "unlisted"
          ? visibility
          : "public",
      duration_seconds:
        Number.isFinite(durationSeconds) && durationSeconds > 0
          ? durationSeconds
          : null,
    })
    .select("id")
    .single<{ id: string }>();

  if (insertError || !video) {
    redirect(
      getStatusRedirect(
        "error",
        "/videos/new",
        insertError?.message ?? "Could not create video.",
      ),
    );
  }

  if (tags.length > 0) {
    const { error: tagError } = await supabase.from("video_tags").insert(
      tags.map((tag) => ({
        video_id: video.id,
        tag,
      })),
    );

    if (tagError) {
      redirect(
        getStatusRedirect(
          "error",
          "/videos/new",
          `Video created, but tags failed: ${tagError.message}`,
        ),
      );
    }
  }

  revalidatePath("/");
  revalidatePath("/dashboard");
  revalidatePath("/feed");
  revalidatePath("/videos/new");
  redirect(getStatusRedirect("success", "/dashboard", "Post published."));
}
