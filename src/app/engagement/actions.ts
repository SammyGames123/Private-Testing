"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

function getSafeRedirectPath(value: FormDataEntryValue | null) {
  const path = typeof value === "string" && value.startsWith("/") ? value : "/";
  return path;
}

export async function toggleLike(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const videoId = String(formData.get("video_id") ?? "");
  const redirectTo = getSafeRedirectPath(formData.get("redirect_to"));

  if (!videoId) {
    redirect(redirectTo);
  }

  const { data: existingLike } = await supabase
    .from("likes")
    .select("video_id")
    .eq("user_id", user.id)
    .eq("video_id", videoId)
    .maybeSingle();

  if (existingLike) {
    await supabase
      .from("likes")
      .delete()
      .eq("user_id", user.id)
      .eq("video_id", videoId);
  } else {
    await supabase.from("likes").insert({
      user_id: user.id,
      video_id: videoId,
    });
  }

  revalidatePath("/");
  revalidatePath("/dashboard");
  redirect(redirectTo);
}

export async function toggleLikeInline(videoId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return {
      ok: false,
      requiresAuth: true,
    };
  }

  if (!videoId) {
    return {
      ok: false,
      requiresAuth: false,
    };
  }

  const { data: existingLike } = await supabase
    .from("likes")
    .select("video_id")
    .eq("user_id", user.id)
    .eq("video_id", videoId)
    .maybeSingle();

  if (existingLike) {
    await supabase
      .from("likes")
      .delete()
      .eq("user_id", user.id)
      .eq("video_id", videoId);
  } else {
    await supabase.from("likes").insert({
      user_id: user.id,
      video_id: videoId,
    });
  }

  revalidatePath("/");
  revalidatePath("/dashboard");
  revalidatePath("/feed");

  return {
    ok: true,
    requiresAuth: false,
    liked: !existingLike,
  };
}

export async function addComment(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const videoId = String(formData.get("video_id") ?? "");
  const body = String(formData.get("body") ?? "").trim();
  const redirectTo = getSafeRedirectPath(formData.get("redirect_to"));

  if (!videoId || !body) {
    redirect(redirectTo);
  }

  await supabase.from("comments").insert({
    user_id: user.id,
    video_id: videoId,
    body,
  });

  revalidatePath("/");
  revalidatePath("/dashboard");
  redirect(redirectTo);
}
