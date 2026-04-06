"use server";

import { createClient } from "@/lib/supabase/server";
import { getStatusRedirect } from "@/lib/utils";
import { redirect } from "next/navigation";

function slugifyUsername(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 24);
}

export async function saveProfile(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const displayName = String(formData.get("display_name") ?? "").trim();
  const usernameInput = String(formData.get("username") ?? "");
  const username = slugifyUsername(usernameInput || displayName || user.email || "");
  const bio = String(formData.get("bio") ?? "").trim();
  const interests = String(formData.get("interests") ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean)
    .slice(0, 12);

  if (!username) {
    redirect(
      getStatusRedirect(
        "error",
        "/profile",
        "Please provide a username or display name.",
      ),
    );
  }

  const { error } = await supabase
    .from("profiles")
    .update({
      display_name: displayName || username,
      username,
      bio: bio || null,
      interests,
      email: user.email ?? null,
    })
    .eq("id", user.id);

  if (error) {
    redirect(getStatusRedirect("error", "/profile", error.message));
  }

  redirect(getStatusRedirect("success", "/profile", "Profile updated."));
}
