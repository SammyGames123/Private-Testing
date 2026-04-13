"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

async function getAuthedSupabase() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  return { supabase, user };
}

function revalidateAll() {
  revalidatePath("/");
  revalidatePath("/feed");
  revalidatePath("/dashboard");
}

export async function editPost(formData: FormData) {
  const videoId = String(formData.get("video_id") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  const caption = String(formData.get("caption") ?? "").trim();

  if (!videoId || !title) {
    return;
  }

  const { supabase, user } = await getAuthedSupabase();

  await supabase
    .from("videos")
    .update({
      title,
      caption: caption || null,
    })
    .eq("id", videoId)
    .eq("creator_id", user.id);

  revalidateAll();
  redirect(`/dashboard/posts/${videoId}`);
}

export async function togglePinPost(formData: FormData) {
  const videoId = String(formData.get("video_id") ?? "").trim();
  const nextPinned = String(formData.get("next") ?? "") === "true";

  if (!videoId) {
    return;
  }

  const { supabase, user } = await getAuthedSupabase();

  await supabase
    .from("videos")
    .update({ is_pinned: nextPinned })
    .eq("id", videoId)
    .eq("creator_id", user.id);

  revalidateAll();
  redirect(`/dashboard/posts/${videoId}`);
}

export async function toggleArchivePost(formData: FormData) {
  const videoId = String(formData.get("video_id") ?? "").trim();
  const nextArchived = String(formData.get("next") ?? "") === "true";

  if (!videoId) {
    return;
  }

  const { supabase, user } = await getAuthedSupabase();

  await supabase
    .from("videos")
    .update({ is_archived: nextArchived })
    .eq("id", videoId)
    .eq("creator_id", user.id);

  revalidateAll();
  redirect(`/dashboard/posts/${videoId}`);
}

export async function deletePost(formData: FormData) {
  const videoId = String(formData.get("video_id") ?? "").trim();

  if (!videoId) {
    return;
  }

  const { supabase, user } = await getAuthedSupabase();

  await supabase
    .from("videos")
    .delete()
    .eq("id", videoId)
    .eq("creator_id", user.id);

  revalidateAll();
  redirect("/dashboard");
}
