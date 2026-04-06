"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

function getSafeRedirectPath(value: FormDataEntryValue | null) {
  const path = typeof value === "string" && value.startsWith("/") ? value : "/";
  return path;
}

export async function toggleFollow(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const targetUserId = String(formData.get("target_user_id") ?? "");
  const redirectTo = getSafeRedirectPath(formData.get("redirect_to"));

  if (!targetUserId || targetUserId === user.id) {
    redirect(redirectTo);
  }

  const { data: existingFollow } = await supabase
    .from("follows")
    .select("following_id")
    .eq("follower_id", user.id)
    .eq("following_id", targetUserId)
    .maybeSingle();

  if (existingFollow) {
    await supabase
      .from("follows")
      .delete()
      .eq("follower_id", user.id)
      .eq("following_id", targetUserId);
  } else {
    await supabase.from("follows").insert({
      follower_id: user.id,
      following_id: targetUserId,
    });
  }

  revalidatePath("/");
  revalidatePath("/dashboard");
  redirect(redirectTo);
}

export async function toggleFollowInline(targetUserId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { ok: false, requiresAuth: true };
  }

  if (!targetUserId || targetUserId === user.id) {
    return { ok: false, requiresAuth: false };
  }

  const { data: existingFollow } = await supabase
    .from("follows")
    .select("following_id")
    .eq("follower_id", user.id)
    .eq("following_id", targetUserId)
    .maybeSingle();

  if (existingFollow) {
    await supabase
      .from("follows")
      .delete()
      .eq("follower_id", user.id)
      .eq("following_id", targetUserId);
  } else {
    await supabase.from("follows").insert({
      follower_id: user.id,
      following_id: targetUserId,
    });
  }

  return { ok: true, requiresAuth: false, following: !existingFollow };
}
